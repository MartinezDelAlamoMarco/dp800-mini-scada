-- Mini-SCADA: una funcion y dos vistas.
-- Se ejecuta entero con F5 despues de 02_datos.sql. Se puede repetir.

USE MiniScada;
GO

-- Funcion: dice si un valor esta por debajo, dentro o por encima del rango normal
CREATE OR ALTER FUNCTION dbo.fn_EstadoValor (
    @Valor     DECIMAL(10,2),
    @MinNormal DECIMAL(10,2),
    @MaxNormal DECIMAL(10,2)
)
RETURNS NVARCHAR(10)
AS
BEGIN
    RETURN CASE
        WHEN @Valor < @MinNormal THEN N'bajo'
        WHEN @Valor > @MaxNormal THEN N'alto'
        ELSE N'normal'
    END;
END;
GO

-- Vista 1: ultima lectura de cada sensor, con su zona y si esta dentro del rango
CREATE OR ALTER VIEW dbo.vw_UltimaLectura
AS
WITH Ordenadas AS (
    SELECT SensorId, FechaHora, Valor,
           ROW_NUMBER() OVER (PARTITION BY SensorId ORDER BY FechaHora DESC) AS Orden
    FROM dbo.Lecturas
)
SELECT z.Nombre AS Zona,
       d.Nombre AS Dispositivo,
       s.Nombre AS Sensor,
       s.Tipo,
       o.FechaHora,
       o.Valor,
       s.Unidad,
       dbo.fn_EstadoValor(o.Valor, s.MinNormal, s.MaxNormal) AS Estado
FROM Ordenadas o
JOIN dbo.Sensores s ON s.SensorId = o.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
JOIN dbo.Zonas z ON z.ZonaId = d.ZonaId
WHERE o.Orden = 1;
GO

-- Vista 2: alarmas con su zona, su sensor y su incidencia (si la tiene).
-- No incluye la columna Embedding, que no sirve para leer.
CREATE OR ALTER VIEW dbo.vw_AlarmasConIncidencia
AS
SELECT a.AlarmaId,
       z.Nombre AS Zona,
       d.Nombre AS Dispositivo,
       s.Nombre AS Sensor,
       a.FechaHora,
       a.Severidad,
       a.Estado,
       a.Descripcion,
       i.Responsable,
       DATEDIFF(MINUTE, i.FechaApertura, i.FechaCierre) AS MinutosResolucion,
       i.Causa,
       i.Solucion
FROM dbo.Alarmas a
JOIN dbo.Sensores s ON s.SensorId = a.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
JOIN dbo.Zonas z ON z.ZonaId = d.ZonaId
LEFT JOIN dbo.Incidencias i ON i.AlarmaId = a.AlarmaId;
GO

-- COMPROBACION ---------------------------------------------------------------

-- La funcion con tres casos: alto, normal y bajo
SELECT dbo.fn_EstadoValor(30.00, 18.00, 27.00) AS Alto,
       dbo.fn_EstadoValor(22.00, 18.00, 27.00) AS Normal,
       dbo.fn_EstadoValor(10.00, 18.00, 27.00) AS Bajo;
GO

-- Vista 1: debe salir una fila por sensor (18)
SELECT * FROM dbo.vw_UltimaLectura ORDER BY Zona, Dispositivo, Sensor;
GO

-- Vista 2: debe salir una fila por alarma (11), con incidencia en 9
SELECT AlarmaId, Zona, Sensor, FechaHora, Severidad, Estado, Responsable, MinutosResolucion, Causa
FROM dbo.vw_AlarmasConIncidencia
ORDER BY AlarmaId;
GO
