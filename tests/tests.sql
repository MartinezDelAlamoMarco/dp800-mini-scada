-- Mini-SCADA: pruebas automaticas.
-- Se ejecuta entero con F5 y al final sale una tabla con OK o FALLO por prueba.
-- Todas las pruebas que tocan datos se hacen dentro de una transaccion que se
-- deshace, asi que se pueden repetir sin ensuciar la base de datos.
-- Se va ampliando con cada fase del proyecto.

USE MiniScada;
GO

CREATE TABLE #Resultados (
    Id        INT IDENTITY(1,1) NOT NULL,
    Prueba    NVARCHAR(120) NOT NULL,
    Resultado NVARCHAR(5) NOT NULL
);
GO

-- FASE 1: estructura

INSERT #Resultados (Prueba, Resultado)
SELECT N'Existen las 8 tablas',
       CASE WHEN (SELECT COUNT(*) FROM sys.tables
                  WHERE name IN ('Zonas', 'Dispositivos', 'Sensores', 'Lecturas',
                                 'Alarmas', 'Incidencias', 'Documentos', 'UsuariosZona')) = 8
            THEN 'OK' ELSE 'FALLO' END;

INSERT #Resultados (Prueba, Resultado)
SELECT N'Las columnas Embedding de Alarmas y Documentos son de tipo vector',
       CASE WHEN (SELECT COUNT(*) FROM sys.columns
                  WHERE name = 'Embedding'
                    AND object_id IN (OBJECT_ID('dbo.Alarmas'), OBJECT_ID('dbo.Documentos'))
                    AND TYPE_NAME(user_type_id) = 'vector') = 2
            THEN 'OK' ELSE 'FALLO' END;

INSERT #Resultados (Prueba, Resultado)
SELECT N'Existen la funcion, las 2 vistas, los 2 procedimientos y el trigger',
       CASE WHEN (SELECT COUNT(*) FROM sys.objects
                  WHERE name IN ('fn_EstadoValor', 'vw_UltimaLectura', 'vw_AlarmasConIncidencia',
                                 'usp_RegistrarAlarma', 'usp_CerrarIncidencia')) = 5
                 AND EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_Incidencias_EstadoAlarma')
            THEN 'OK' ELSE 'FALLO' END;
GO

-- FASE 1: datos

INSERT #Resultados (Prueba, Resultado)
SELECT N'Lecturas tiene mas de 500.000 filas',
       CASE WHEN (SELECT COUNT(*) FROM dbo.Lecturas) > 500000 THEN 'OK' ELSE 'FALLO' END;

INSERT #Resultados (Prueba, Resultado)
SELECT N'La vista de ultimas lecturas tiene una fila por sensor',
       CASE WHEN (SELECT COUNT(*) FROM dbo.vw_UltimaLectura) = (SELECT COUNT(*) FROM dbo.Sensores)
            THEN 'OK' ELSE 'FALLO' END;

INSERT #Resultados (Prueba, Resultado)
SELECT N'Toda alarma cerrada tiene una incidencia con fecha de cierre',
       CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.Alarmas a
                             WHERE a.Estado = 'cerrada'
                               AND NOT EXISTS (SELECT 1 FROM dbo.Incidencias i
                                               WHERE i.AlarmaId = a.AlarmaId AND i.FechaCierre IS NOT NULL))
            THEN 'OK' ELSE 'FALLO' END;
GO

-- FASE 1: restricciones, procedimientos y trigger

-- El CHECK debe rechazar un sensor con el minimo mayor que el maximo
DECLARE @Rechazado BIT = 0;
BEGIN TRY
    BEGIN TRAN;
    INSERT dbo.Sensores (DispositivoId, Nombre, Tipo, Unidad, MinNormal, MaxNormal)
    SELECT TOP 1 DispositivoId, N'Prueba', 'co2', N'ppm', 100, 50 FROM dbo.Dispositivos;
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @Rechazado = 1;
END CATCH;
INSERT #Resultados (Prueba, Resultado)
VALUES (N'El CHECK rechaza un sensor con el rango normal al reves',
        CASE WHEN @Rechazado = 1 THEN 'OK' ELSE 'FALLO' END);
GO

-- El procedimiento debe rechazar un sensor que no existe (error 50001)
DECLARE @Numero INT = 0, @Id INT;
BEGIN TRY
    EXEC dbo.usp_RegistrarAlarma @SensorId = -1, @Severidad = 'media',
         @Descripcion = N'Prueba', @AlarmaId = @Id OUTPUT;
END TRY
BEGIN CATCH
    SET @Numero = ERROR_NUMBER();
END CATCH;
INSERT #Resultados (Prueba, Resultado)
VALUES (N'usp_RegistrarAlarma rechaza un sensor que no existe',
        CASE WHEN @Numero = 50001 THEN 'OK' ELSE 'FALLO' END);
GO

-- El trigger debe cerrar la alarma al cerrar su incidencia
DECLARE @Sensor INT = (SELECT s.SensorId FROM dbo.Sensores s
                       JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                       WHERE d.Nombre = N'Nodo-Oficina-2' AND s.Nombre = N'CO2');
DECLARE @Alarma INT, @Estado NVARCHAR(15) = N'error';
BEGIN TRY
    BEGIN TRAN;
    EXEC dbo.usp_RegistrarAlarma @SensorId = @Sensor, @Severidad = 'media',
         @Descripcion = N'Prueba', @AlarmaId = @Alarma OUTPUT;
    INSERT dbo.Incidencias (AlarmaId, Responsable, FechaApertura)
    VALUES (@Alarma, N'tecnico_oficinas', SYSDATETIME());
    EXEC dbo.usp_CerrarIncidencia @AlarmaId = @Alarma, @Responsable = N'tecnico_oficinas',
         @Causa = N'Prueba', @Solucion = N'Prueba';
    SELECT @Estado = Estado FROM dbo.Alarmas WHERE AlarmaId = @Alarma;
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH;
INSERT #Resultados (Prueba, Resultado)
VALUES (N'El trigger cierra la alarma cuando se cierra su incidencia',
        CASE WHEN @Estado = 'cerrada' THEN 'OK' ELSE 'FALLO' END);
GO

-- FASE 2: seguridad y optimizacion

INSERT #Resultados (Prueba, Resultado)
SELECT N'La politica de seguridad por filas esta activa',
       CASE WHEN EXISTS (SELECT 1 FROM sys.security_policies
                         WHERE name = 'PoliticaZonas' AND is_enabled = 1)
            THEN 'OK' ELSE 'FALLO' END;

INSERT #Resultados (Prueba, Resultado)
SELECT N'Existe el indice IX_Lecturas_Sensor_Fecha',
       CASE WHEN EXISTS (SELECT 1 FROM sys.indexes
                         WHERE name = 'IX_Lecturas_Sensor_Fecha'
                           AND object_id = OBJECT_ID('dbo.Lecturas'))
            THEN 'OK' ELSE 'FALLO' END;
GO

-- El administrador ve las 11 alarmas y el tecnico de la sala de servidores solo 3
DECLARE @Admin INT = -1, @Tecnico INT = -1;
BEGIN TRY
    EXECUTE AS USER = 'admin_scada';
    SELECT @Admin = COUNT(*) FROM dbo.Alarmas;
    REVERT;
    EXECUTE AS USER = 'tecnico_cpd';
    SELECT @Tecnico = COUNT(*) FROM dbo.Alarmas;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
END CATCH;
INSERT #Resultados (Prueba, Resultado)
VALUES (N'El administrador ve 11 alarmas y el tecnico de la sala de servidores 3',
        CASE WHEN @Admin = 11 AND @Tecnico = 3 THEN 'OK' ELSE 'FALLO' END);
GO

-- El tecnico no puede leer la tabla Lecturas directamente (error 229)
DECLARE @Numero INT = 0;
BEGIN TRY
    EXECUTE AS USER = 'tecnico_cpd';
    SELECT COUNT(*) FROM dbo.Lecturas;
    REVERT;
END TRY
BEGIN CATCH
    SET @Numero = ERROR_NUMBER();
    REVERT;
END CATCH;
INSERT #Resultados (Prueba, Resultado)
VALUES (N'El tecnico no puede leer la tabla Lecturas',
        CASE WHEN @Numero = 229 THEN 'OK' ELSE 'FALLO' END);
GO

-- El email de contacto sale completo para el administrador y tapado para el tecnico
DECLARE @EmailAdmin NVARCHAR(150) = N'', @EmailTecnico NVARCHAR(150) = N'';
BEGIN TRY
    EXECUTE AS USER = 'admin_scada';
    SELECT TOP 1 @EmailAdmin = ContactoEmail FROM dbo.Zonas ORDER BY ZonaId;
    REVERT;
    EXECUTE AS USER = 'tecnico_oficinas';
    SELECT TOP 1 @EmailTecnico = ContactoEmail FROM dbo.Zonas ORDER BY ZonaId;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
END CATCH;
INSERT #Resultados (Prueba, Resultado)
VALUES (N'El email de contacto sale tapado para el tecnico y completo para el administrador',
        CASE WHEN @EmailAdmin LIKE N'%@miniscada.example'
                  AND @EmailTecnico LIKE N'%XXXX.com'
             THEN 'OK' ELSE 'FALLO' END);
GO

-- RESULTADO

SELECT Prueba, Resultado FROM #Resultados ORDER BY Id;

SELECT SUM(CASE WHEN Resultado = 'OK' THEN 1 ELSE 0 END) AS Correctas,
       SUM(CASE WHEN Resultado = 'FALLO' THEN 1 ELSE 0 END) AS Fallidas
FROM #Resultados;
GO

DROP TABLE #Resultados;
GO
