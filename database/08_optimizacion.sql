-- Mini-SCADA: optimizacion de una consulta.
-- La consulta: media de un sensor en una semana (el CO2 de la oficina 1, del 1 al
-- 8 de agosto de 2026). Se mide dos veces: sin indice y con indice.
--
-- Como ejecutarlo, bloque a bloque y EN ORDEN, en la misma ventana de SSMS
-- (selecciona el bloque y pulsa F5):
--   1. Bloque 1: quita el indice si existe, para poder repetir la prueba.
--   2. Bloque 2 (ANTES): con "Incluir plan de ejecucion real" (Ctrl+M) activado.
--      Se ejecuta dos veces: la primera con la cache vacia y la segunda con ella caliente.
--   3. Bloque 3: crea el indice.
--   4. Bloque 4 (DESPUES): igual que el 2, con la cache vacia y luego caliente.
--   5. Bloque 5: espacio que ocupa cada indice.
--
-- En la pestana Mensajes se ven las lecturas logicas y los tiempos de cada ejecucion.
-- DBCC DROPCLEANBUFFERS vacia la cache de datos para que la primera ejecucion de
-- cada bloque parta de cero. Hacerlo solo en un equipo de pruebas.

USE MiniScada;
GO

-- Bloque 1: quitar el indice si existe, para empezar sin el
DROP INDEX IF EXISTS IX_Lecturas_Sensor_Fecha ON dbo.Lecturas;
GO

-- Bloque 2: ANTES. Solo existe la clave primaria de Lecturas (por LecturaId).
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

CHECKPOINT;
DBCC DROPCLEANBUFFERS;

DECLARE @SensorId INT = (SELECT s.SensorId FROM dbo.Sensores s
                         JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                         WHERE d.Nombre = N'Nodo-Oficina-1' AND s.Nombre = N'CO2');
DECLARE @Desde DATETIME2(0) = '2026-08-01T00:00:00', @Hasta DATETIME2(0) = '2026-08-08T00:00:00';

-- Primera ejecucion: cache vacia
SELECT AVG(Valor) AS MediaCO2, COUNT(*) AS Lecturas
FROM dbo.Lecturas
WHERE SensorId = @SensorId AND FechaHora >= @Desde AND FechaHora < @Hasta
OPTION (RECOMPILE);

-- Segunda ejecucion: cache caliente
SELECT AVG(Valor) AS MediaCO2, COUNT(*) AS Lecturas
FROM dbo.Lecturas
WHERE SensorId = @SensorId AND FechaHora >= @Desde AND FechaHora < @Hasta
OPTION (RECOMPILE);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Bloque 3: crear el indice. Busca por sensor y fecha, y lleva el valor dentro
-- para no tener que ir a la tabla a leerlo (indice "cubriente").
CREATE NONCLUSTERED INDEX IX_Lecturas_Sensor_Fecha
ON dbo.Lecturas (SensorId, FechaHora)
INCLUDE (Valor);
GO

-- Bloque 4: DESPUES. La misma consulta, ahora con el indice.
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

CHECKPOINT;
DBCC DROPCLEANBUFFERS;

DECLARE @SensorId INT = (SELECT s.SensorId FROM dbo.Sensores s
                         JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                         WHERE d.Nombre = N'Nodo-Oficina-1' AND s.Nombre = N'CO2');
DECLARE @Desde DATETIME2(0) = '2026-08-01T00:00:00', @Hasta DATETIME2(0) = '2026-08-08T00:00:00';

-- Primera ejecucion: cache vacia
SELECT AVG(Valor) AS MediaCO2, COUNT(*) AS Lecturas
FROM dbo.Lecturas
WHERE SensorId = @SensorId AND FechaHora >= @Desde AND FechaHora < @Hasta
OPTION (RECOMPILE);

-- Segunda ejecucion: cache caliente
SELECT AVG(Valor) AS MediaCO2, COUNT(*) AS Lecturas
FROM dbo.Lecturas
WHERE SensorId = @SensorId AND FechaHora >= @Desde AND FechaHora < @Hasta
OPTION (RECOMPILE);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Bloque 5: lo que cuesta el indice, en espacio en disco
SELECT i.name AS Indice, i.type_desc AS Tipo,
       CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS DECIMAL(10,1)) AS MB
FROM sys.indexes i
JOIN sys.dm_db_partition_stats ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('dbo.Lecturas')
GROUP BY i.name, i.type_desc
ORDER BY MB DESC;
GO
