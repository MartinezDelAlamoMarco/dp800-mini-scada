-- Mini-SCADA: creacion de las tablas.
-- Se puede ejecutar entero con F5. Si las tablas ya existen, las borra y las
-- vuelve a crear, asi que se pierden los datos que hubiera.

IF DB_ID('MiniScada') IS NULL CREATE DATABASE MiniScada;
GO
USE MiniScada;
GO

-- Si ya se ejecuto 06_seguridad.sql, primero hay que quitar la politica y las
-- funciones de seguridad, porque dependen de las tablas y impiden borrarlas.
IF OBJECT_ID('Seguridad.PoliticaZonas', 'SP') IS NOT NULL
    DROP SECURITY POLICY Seguridad.PoliticaZonas;
GO
IF OBJECT_ID('Seguridad.fn_AlarmaPermitida') IS NOT NULL DROP FUNCTION Seguridad.fn_AlarmaPermitida;
IF OBJECT_ID('Seguridad.fn_SensorPermitido') IS NOT NULL DROP FUNCTION Seguridad.fn_SensorPermitido;
IF OBJECT_ID('Seguridad.fn_DispositivoPermitido') IS NOT NULL DROP FUNCTION Seguridad.fn_DispositivoPermitido;
IF OBJECT_ID('Seguridad.fn_ZonaPermitida') IS NOT NULL DROP FUNCTION Seguridad.fn_ZonaPermitida;
GO

-- Borrado en orden inverso a las dependencias
DROP TABLE IF EXISTS dbo.Incidencias;
DROP TABLE IF EXISTS dbo.Alarmas;
DROP TABLE IF EXISTS dbo.Lecturas;
DROP TABLE IF EXISTS dbo.Sensores;
DROP TABLE IF EXISTS dbo.Dispositivos;
DROP TABLE IF EXISTS dbo.UsuariosZona;
DROP TABLE IF EXISTS dbo.Documentos;
DROP TABLE IF EXISTS dbo.Zonas;
GO

-- Zonas: areas o edificios donde estan los equipos
CREATE TABLE dbo.Zonas (
    ZonaId        INT IDENTITY(1,1) NOT NULL,
    Nombre        NVARCHAR(100) NOT NULL,
    Descripcion   NVARCHAR(200) NULL,
    ContactoEmail NVARCHAR(150) NULL,   -- dato que luego se enmascara (Dynamic Data Masking)
    CONSTRAINT PK_Zonas PRIMARY KEY (ZonaId),
    CONSTRAINT UQ_Zonas_Nombre UNIQUE (Nombre)
);
GO

-- Dispositivos: nodos IoT de cada zona
CREATE TABLE dbo.Dispositivos (
    DispositivoId INT IDENTITY(1,1) NOT NULL,
    ZonaId        INT NOT NULL,
    Nombre        NVARCHAR(100) NOT NULL,
    Modelo        NVARCHAR(100) NULL,
    Estado        NVARCHAR(20) NOT NULL CONSTRAINT DF_Dispositivos_Estado DEFAULT 'activo',
    FechaAlta     DATE NOT NULL CONSTRAINT DF_Dispositivos_FechaAlta DEFAULT (CONVERT(date, GETDATE())),
    CONSTRAINT PK_Dispositivos PRIMARY KEY (DispositivoId),
    CONSTRAINT FK_Dispositivos_Zonas FOREIGN KEY (ZonaId) REFERENCES dbo.Zonas (ZonaId),
    CONSTRAINT UQ_Dispositivos_ZonaNombre UNIQUE (ZonaId, Nombre),
    CONSTRAINT CK_Dispositivos_Estado CHECK (Estado IN ('activo', 'inactivo', 'mantenimiento'))
);
GO

-- Sensores: cada sensor de un dispositivo y que mide, con su rango normal
CREATE TABLE dbo.Sensores (
    SensorId      INT IDENTITY(1,1) NOT NULL,
    DispositivoId INT NOT NULL,
    Nombre        NVARCHAR(100) NOT NULL,
    Tipo          NVARCHAR(30) NOT NULL,
    Unidad        NVARCHAR(15) NOT NULL,
    MinNormal     DECIMAL(10,2) NOT NULL,
    MaxNormal     DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_Sensores PRIMARY KEY (SensorId),
    CONSTRAINT FK_Sensores_Dispositivos FOREIGN KEY (DispositivoId) REFERENCES dbo.Dispositivos (DispositivoId),
    CONSTRAINT UQ_Sensores_DispositivoNombre UNIQUE (DispositivoId, Nombre),
    CONSTRAINT CK_Sensores_Tipo CHECK (Tipo IN ('temperatura', 'humedad', 'co2', 'presion', 'caudal', 'consumo')),
    CONSTRAINT CK_Sensores_Rango CHECK (MinNormal < MaxNormal)
);
GO

-- Lecturas: historico de mediciones. Es la tabla grande (mas de 500.000 filas).
-- De momento solo tiene la clave primaria, sin indice por sensor y fecha: ese
-- indice se crea mas adelante para medir la mejora de rendimiento.
CREATE TABLE dbo.Lecturas (
    LecturaId   BIGINT IDENTITY(1,1) NOT NULL,
    SensorId    INT NOT NULL,
    FechaHora   DATETIME2(0) NOT NULL,
    Valor       DECIMAL(10,2) NOT NULL,
    PayloadJson NVARCHAR(400) NULL,     -- mensaje original del dispositivo
    CONSTRAINT PK_Lecturas PRIMARY KEY (LecturaId),
    CONSTRAINT FK_Lecturas_Sensores FOREIGN KEY (SensorId) REFERENCES dbo.Sensores (SensorId),
    CONSTRAINT CK_Lecturas_Json CHECK (PayloadJson IS NULL OR ISJSON(PayloadJson) = 1)
);
GO

-- Alarmas: eventos anomalos de un sensor, con su embedding
CREATE TABLE dbo.Alarmas (
    AlarmaId    INT IDENTITY(1,1) NOT NULL,
    SensorId    INT NOT NULL,
    FechaHora   DATETIME2(0) NOT NULL,
    Severidad   NVARCHAR(10) NOT NULL,
    Descripcion NVARCHAR(500) NOT NULL,
    Estado      NVARCHAR(15) NOT NULL CONSTRAINT DF_Alarmas_Estado DEFAULT 'abierta',
    Embedding   VECTOR(768) NULL,       -- se rellena en la fase de embeddings
    CONSTRAINT PK_Alarmas PRIMARY KEY (AlarmaId),
    CONSTRAINT FK_Alarmas_Sensores FOREIGN KEY (SensorId) REFERENCES dbo.Sensores (SensorId),
    CONSTRAINT CK_Alarmas_Severidad CHECK (Severidad IN ('baja', 'media', 'alta', 'critica')),
    CONSTRAINT CK_Alarmas_Estado CHECK (Estado IN ('abierta', 'en curso', 'cerrada'))
);
GO

-- Incidencias: como se resolvio cada alarma
CREATE TABLE dbo.Incidencias (
    IncidenciaId   INT IDENTITY(1,1) NOT NULL,
    AlarmaId       INT NOT NULL,
    Responsable    NVARCHAR(100) NOT NULL,
    FechaApertura  DATETIME2(0) NOT NULL,
    FechaCierre    DATETIME2(0) NULL,
    Causa          NVARCHAR(500) NULL,
    Solucion       NVARCHAR(1000) NULL,
    CONSTRAINT PK_Incidencias PRIMARY KEY (IncidenciaId),
    CONSTRAINT FK_Incidencias_Alarmas FOREIGN KEY (AlarmaId) REFERENCES dbo.Alarmas (AlarmaId),
    CONSTRAINT CK_Incidencias_Fechas CHECK (FechaCierre IS NULL OR FechaCierre >= FechaApertura)
);
GO

-- Documentos: manuales y procedimientos, con su embedding
CREATE TABLE dbo.Documentos (
    DocumentoId INT IDENTITY(1,1) NOT NULL,
    Titulo      NVARCHAR(200) NOT NULL,
    Tipo        NVARCHAR(30) NOT NULL,
    Contenido   NVARCHAR(MAX) NOT NULL,
    Embedding   VECTOR(768) NULL,       -- se rellena en la fase de embeddings
    CONSTRAINT PK_Documentos PRIMARY KEY (DocumentoId),
    CONSTRAINT CK_Documentos_Tipo CHECK (Tipo IN ('manual', 'procedimiento', 'guia'))
);
GO

-- UsuariosZona: que zonas ve cada usuario (para la seguridad por filas)
CREATE TABLE dbo.UsuariosZona (
    NombreUsuario SYSNAME NOT NULL,
    ZonaId        INT NOT NULL,
    CONSTRAINT PK_UsuariosZona PRIMARY KEY (NombreUsuario, ZonaId),
    CONSTRAINT FK_UsuariosZona_Zonas FOREIGN KEY (ZonaId) REFERENCES dbo.Zonas (ZonaId)
);
GO

-- Comprobacion: tablas creadas con su numero de columnas y de claves foraneas
SELECT t.name AS Tabla,
       (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS Columnas,
       (SELECT COUNT(*) FROM sys.foreign_keys f WHERE f.parent_object_id = t.object_id) AS ClavesForaneas
FROM sys.tables t
WHERE t.is_ms_shipped = 0
ORDER BY t.name;
GO
