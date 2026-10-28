-- Mini-SCADA: seguridad.
-- Se ejecuta entero con F5 despues de 05_consultas_avanzadas.sql. Se puede repetir.
--
-- Que hace:
--   1. Crea dos roles (administrador y tecnico) y cuatro usuarios SIN LOGIN, que
--      solo se pueden usar con EXECUTE AS desde esta base de datos.
--   2. Seguridad por filas (Row-Level Security): cada tecnico ve solo las zonas
--      que tiene en la tabla UsuariosZona. El administrador lo ve todo.
--   3. Enmascarado de datos (Dynamic Data Masking) en el email de contacto de Zonas.
--   4. Permisos con GRANT y DENY para cada rol.
--
-- La tabla Lecturas (500.000 filas) no lleva seguridad por filas para no cargar
-- cada consulta con una comprobacion fila a fila. En su lugar, el tecnico no
-- puede leerla directamente (DENY) y la consulta a traves de la vista
-- vw_LecturasVisibles, que solo deja pasar los sensores que su zona le permite ver.

USE MiniScada;
GO

-- Limpieza para poder repetir el script ------------------------------------

IF OBJECT_ID('Seguridad.PoliticaZonas', 'SP') IS NOT NULL
    DROP SECURITY POLICY Seguridad.PoliticaZonas;
GO
DROP FUNCTION IF EXISTS Seguridad.fn_AlarmaPermitida;
DROP FUNCTION IF EXISTS Seguridad.fn_SensorPermitido;
DROP FUNCTION IF EXISTS Seguridad.fn_DispositivoPermitido;
DROP FUNCTION IF EXISTS Seguridad.fn_ZonaPermitida;
GO

-- 1. Roles y usuarios -------------------------------------------------------

IF DATABASE_PRINCIPAL_ID('rol_admin_scada') IS NULL CREATE ROLE rol_admin_scada;
IF DATABASE_PRINCIPAL_ID('rol_tecnico') IS NULL CREATE ROLE rol_tecnico;
GO

IF DATABASE_PRINCIPAL_ID('admin_scada') IS NULL CREATE USER admin_scada WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('tecnico_cpd') IS NULL CREATE USER tecnico_cpd WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('tecnico_oficinas') IS NULL CREATE USER tecnico_oficinas WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('tecnico_almacen') IS NULL CREATE USER tecnico_almacen WITHOUT LOGIN;
GO

IF ISNULL(IS_ROLEMEMBER('rol_admin_scada', 'admin_scada'), 0) = 0 ALTER ROLE rol_admin_scada ADD MEMBER admin_scada;
IF ISNULL(IS_ROLEMEMBER('rol_tecnico', 'tecnico_cpd'), 0) = 0 ALTER ROLE rol_tecnico ADD MEMBER tecnico_cpd;
IF ISNULL(IS_ROLEMEMBER('rol_tecnico', 'tecnico_oficinas'), 0) = 0 ALTER ROLE rol_tecnico ADD MEMBER tecnico_oficinas;
IF ISNULL(IS_ROLEMEMBER('rol_tecnico', 'tecnico_almacen'), 0) = 0 ALTER ROLE rol_tecnico ADD MEMBER tecnico_almacen;
GO

-- 2. Seguridad por filas ----------------------------------------------------

IF SCHEMA_ID('Seguridad') IS NULL EXEC ('CREATE SCHEMA Seguridad');
GO

-- Cada funcion devuelve una fila si el usuario puede ver ese dato y ninguna si
-- no. Dejan pasar siempre al administrador y a db_owner (para no quedarme yo
-- sin ver datos al trabajar). El resto solo ve las zonas de UsuariosZona.

CREATE FUNCTION Seguridad.fn_ZonaPermitida (@ZonaId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Permitido
    WHERE IS_ROLEMEMBER('rol_admin_scada') = 1
       OR IS_ROLEMEMBER('db_owner') = 1
       OR EXISTS (SELECT 1 FROM dbo.UsuariosZona uz
                  WHERE uz.ZonaId = @ZonaId AND uz.NombreUsuario = USER_NAME());
GO

CREATE FUNCTION Seguridad.fn_DispositivoPermitido (@DispositivoId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Permitido
    WHERE IS_ROLEMEMBER('rol_admin_scada') = 1
       OR IS_ROLEMEMBER('db_owner') = 1
       OR EXISTS (SELECT 1
                  FROM dbo.Dispositivos d
                  JOIN dbo.UsuariosZona uz ON uz.ZonaId = d.ZonaId
                  WHERE d.DispositivoId = @DispositivoId AND uz.NombreUsuario = USER_NAME());
GO

CREATE FUNCTION Seguridad.fn_SensorPermitido (@SensorId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Permitido
    WHERE IS_ROLEMEMBER('rol_admin_scada') = 1
       OR IS_ROLEMEMBER('db_owner') = 1
       OR EXISTS (SELECT 1
                  FROM dbo.Sensores s
                  JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                  JOIN dbo.UsuariosZona uz ON uz.ZonaId = d.ZonaId
                  WHERE s.SensorId = @SensorId AND uz.NombreUsuario = USER_NAME());
GO

CREATE FUNCTION Seguridad.fn_AlarmaPermitida (@AlarmaId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Permitido
    WHERE IS_ROLEMEMBER('rol_admin_scada') = 1
       OR IS_ROLEMEMBER('db_owner') = 1
       OR EXISTS (SELECT 1
                  FROM dbo.Alarmas a
                  JOIN dbo.Sensores s ON s.SensorId = a.SensorId
                  JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                  JOIN dbo.UsuariosZona uz ON uz.ZonaId = d.ZonaId
                  WHERE a.AlarmaId = @AlarmaId AND uz.NombreUsuario = USER_NAME());
GO

-- Politica: un filtro (para no ver lo ajeno) en cada tabla, y un bloqueo al
-- insertar en Alarmas e Incidencias (para no crear datos en una zona ajena).
CREATE SECURITY POLICY Seguridad.PoliticaZonas
    ADD FILTER PREDICATE Seguridad.fn_ZonaPermitida(ZonaId) ON dbo.Zonas,
    ADD FILTER PREDICATE Seguridad.fn_ZonaPermitida(ZonaId) ON dbo.Dispositivos,
    ADD FILTER PREDICATE Seguridad.fn_DispositivoPermitido(DispositivoId) ON dbo.Sensores,
    ADD FILTER PREDICATE Seguridad.fn_SensorPermitido(SensorId) ON dbo.Alarmas,
    ADD BLOCK PREDICATE Seguridad.fn_SensorPermitido(SensorId) ON dbo.Alarmas AFTER INSERT,
    ADD FILTER PREDICATE Seguridad.fn_AlarmaPermitida(AlarmaId) ON dbo.Incidencias,
    ADD BLOCK PREDICATE Seguridad.fn_AlarmaPermitida(AlarmaId) ON dbo.Incidencias AFTER INSERT
WITH (STATE = ON);
GO

-- Lecturas visibles: hereda la seguridad de la tabla Sensores. Un tecnico solo
-- ve las lecturas de los sensores que la politica le deja ver.
CREATE OR ALTER VIEW dbo.vw_LecturasVisibles
AS
SELECT l.LecturaId, l.SensorId, l.FechaHora, l.Valor
FROM dbo.Lecturas l
WHERE EXISTS (SELECT 1 FROM dbo.Sensores s WHERE s.SensorId = l.SensorId);
GO

-- 3. Enmascarado de datos ---------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.masked_columns
               WHERE object_id = OBJECT_ID('dbo.Zonas') AND name = 'ContactoEmail')
    ALTER TABLE dbo.Zonas ALTER COLUMN ContactoEmail ADD MASKED WITH (FUNCTION = 'email()');
GO

-- 4. Permisos ---------------------------------------------------------------

-- Administrador: todo en el esquema dbo, y ver los datos sin enmascarar
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO rol_admin_scada;
GRANT UNMASK TO rol_admin_scada;
GO

-- Tecnico: leer lo que necesita, usar los dos procedimientos y nada mas
GRANT SELECT ON dbo.Zonas TO rol_tecnico;
GRANT SELECT ON dbo.Dispositivos TO rol_tecnico;
GRANT SELECT ON dbo.Sensores TO rol_tecnico;
GRANT SELECT ON dbo.Alarmas TO rol_tecnico;
GRANT SELECT ON dbo.Incidencias TO rol_tecnico;
GRANT SELECT ON dbo.Documentos TO rol_tecnico;
GRANT SELECT ON dbo.vw_UltimaLectura TO rol_tecnico;
GRANT SELECT ON dbo.vw_AlarmasConIncidencia TO rol_tecnico;
GRANT SELECT ON dbo.vw_LecturasVisibles TO rol_tecnico;
GRANT EXECUTE ON dbo.usp_RegistrarAlarma TO rol_tecnico;
GRANT EXECUTE ON dbo.usp_CerrarIncidencia TO rol_tecnico;
GRANT EXECUTE ON dbo.fn_EstadoValor TO rol_tecnico;

-- Lo que el tecnico no puede hacer: tocar Lecturas directamente, cambiar la
-- estructura de la instalacion ni borrar alarmas o incidencias.
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Lecturas TO rol_tecnico;
DENY INSERT, UPDATE, DELETE ON dbo.Zonas TO rol_tecnico;
DENY INSERT, UPDATE, DELETE ON dbo.Dispositivos TO rol_tecnico;
DENY INSERT, UPDATE, DELETE ON dbo.Sensores TO rol_tecnico;
DENY DELETE ON dbo.Alarmas TO rol_tecnico;
DENY DELETE ON dbo.Incidencias TO rol_tecnico;
GO

-- COMPROBACION ---------------------------------------------------------------

-- Usuarios y roles creados
SELECT r.name AS Rol, m.name AS Usuario
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name IN ('rol_admin_scada', 'rol_tecnico')
ORDER BY r.name, m.name;

-- Politica activa y tablas que protege
SELECT p.name AS Politica, p.is_enabled AS Activa,
       OBJECT_NAME(pr.target_object_id) AS Tabla, pr.predicate_type_desc AS Tipo
FROM sys.security_policies p
JOIN sys.security_predicates pr ON pr.object_id = p.object_id
ORDER BY Tabla, Tipo;

-- Columna enmascarada
SELECT OBJECT_NAME(object_id) AS Tabla, name AS Columna, masking_function AS Mascara
FROM sys.masked_columns;
GO
