-- Mini-SCADA: consultas avanzadas con CTE, funciones de ventana y JSON.
-- Son solo consultas (no cambian nada). Se ejecuta cada bloque por separado, o
-- todo con F5 y se ven los resultados uno debajo de otro.

USE MiniScada;
GO

-- CTE 1: dias en que algun sensor se salio de su rango normal.
-- Primero se resumen las lecturas por sensor y dia, y luego se compara con el rango.
WITH Diario AS (
    SELECT SensorId,
           CAST(FechaHora AS DATE) AS Dia,
           MIN(Valor) AS Minimo,
           MAX(Valor) AS Maximo
    FROM dbo.Lecturas
    GROUP BY SensorId, CAST(FechaHora AS DATE)
)
SELECT di.Dia, d.Nombre AS Dispositivo, s.Nombre AS Sensor,
       di.Minimo, di.Maximo, s.MinNormal, s.MaxNormal
FROM Diario di
JOIN dbo.Sensores s ON s.SensorId = di.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE di.Maximo > s.MaxNormal OR di.Minimo < s.MinNormal
ORDER BY di.Dia, d.Nombre, s.Nombre;
GO

-- CTE 2: sensores "planos". Se agrupan las lecturas por hora y se buscan las horas
-- con las 12 lecturas y desviacion cero, es decir, con el mismo valor todo el rato.
-- Esto encuentra los CO2 que se quedan fijos aunque su valor este dentro del rango.
WITH PorHora AS (
    SELECT SensorId,
           DATEADD(HOUR, DATEDIFF(HOUR, 0, FechaHora), 0) AS Hora,
           COUNT(*) AS Lecturas,
           STDEV(Valor) AS Desviacion
    FROM dbo.Lecturas
    GROUP BY SensorId, DATEADD(HOUR, DATEDIFF(HOUR, 0, FechaHora), 0)
)
SELECT d.Nombre AS Dispositivo, s.Nombre AS Sensor,
       MIN(p.Hora) AS Desde, MAX(p.Hora) AS UltimaHoraPlana, COUNT(*) AS HorasPlanas
FROM PorHora p
JOIN dbo.Sensores s ON s.SensorId = p.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE p.Lecturas >= 12 AND p.Desviacion = 0
GROUP BY d.Nombre, s.Nombre
ORDER BY Desde;
GO

-- Ventana 1: alarmas de cada zona, con su puesto segun lo que tardaron en
-- resolverse (RANK) y el numero de alarmas acumuladas en la zona (COUNT OVER).
SELECT Zona, AlarmaId, FechaHora, Severidad, MinutosResolucion,
       RANK() OVER (PARTITION BY Zona ORDER BY MinutosResolucion DESC) AS PuestoPorDuracion,
       COUNT(*) OVER (PARTITION BY Zona ORDER BY FechaHora
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AlarmasAcumuladas
FROM dbo.vw_AlarmasConIncidencia
ORDER BY Zona, FechaHora;
GO

-- Ventana 2: media movil de la ultima hora (12 lecturas) de la temperatura de la
-- sala de servidores el dia del fallo de refrigeracion, 15 de julio. Se calcula
-- con todas las lecturas y luego se muestra una por hora.
WITH Movil AS (
    SELECT l.FechaHora, l.Valor,
           AVG(l.Valor) OVER (ORDER BY l.FechaHora ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS MediaUltimaHora
    FROM dbo.Lecturas l
    JOIN dbo.Sensores s ON s.SensorId = l.SensorId
    JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
    WHERE d.Nombre = N'Nodo-CPD-1' AND s.Nombre = N'Temperatura'
      AND l.FechaHora >= '2026-07-15T08:00:00' AND l.FechaHora < '2026-07-15T20:00:00'
)
SELECT FechaHora, Valor, CAST(MediaUltimaHora AS DECIMAL(10,2)) AS MediaUltimaHora
FROM Movil
WHERE DATEPART(MINUTE, FechaHora) = 0
ORDER BY FechaHora;
GO

-- JSON 1: bateria media y senal minima de cada dispositivo, leyendo el mensaje
-- original de cada lectura (PayloadJson) con JSON_VALUE.
SELECT d.Nombre AS Dispositivo,
       COUNT(*) AS Lecturas,
       ROUND(AVG(CAST(JSON_VALUE(l.PayloadJson, '$.bateria') AS FLOAT)), 1) AS BateriaMedia,
       MIN(CAST(JSON_VALUE(l.PayloadJson, '$.rssi') AS INT)) AS SenalMinima
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
GROUP BY d.Nombre
ORDER BY BateriaMedia;
GO

-- JSON 2: un mensaje abierto con OPENJSON, una fila por cada campo.
SELECT j.[key] AS Campo, j.value AS Valor
FROM (SELECT TOP 1 PayloadJson FROM dbo.Lecturas ORDER BY LecturaId) l
CROSS APPLY OPENJSON(l.PayloadJson) j;
GO
