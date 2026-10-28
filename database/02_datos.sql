-- Mini-SCADA: datos simulados.
-- Se ejecuta entero con F5 despues de 01_tablas.sql. Tarda entre 20 segundos y
-- un par de minutos, segun el equipo. Se puede repetir: borra los datos de las
-- tablas (menos Documentos, que se carga en otro script) y los vuelve a crear.
--
-- Los datos son siempre los mismos: el "ruido" de las lecturas sale de un hash
-- MD5 del sensor y del numero de lectura, y no de numeros aleatorios, asi que
-- cualquiera que lo ejecute obtiene exactamente lo mismo.
--
-- Lecturas: 18 sensores, una lectura cada 5 minutos durante 100 dias
-- (del 20 de junio al 27 de septiembre de 2026), unas 518.000 filas.
-- Despues se meten a proposito 11 anomalias y 11 alarmas relacionadas con ellas.

USE MiniScada;
GO

DELETE FROM dbo.Incidencias;
DELETE FROM dbo.Alarmas;
DELETE FROM dbo.Lecturas;
DELETE FROM dbo.Sensores;
DELETE FROM dbo.Dispositivos;
DELETE FROM dbo.UsuariosZona;
DELETE FROM dbo.Zonas;
GO

-- Reinicia los numeros de identidad para que cada ejecucion empiece en 1 y los
-- identificadores salgan siempre iguales. Solo se reinician las tablas que ya
-- han tenido filas (en una tabla nueva, RESEED 0 haria empezar en 0).
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Incidencias') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Incidencias', RESEED, 0);
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Alarmas') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Alarmas', RESEED, 0);
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Lecturas') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Lecturas', RESEED, 0);
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Sensores') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Sensores', RESEED, 0);
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Dispositivos') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Dispositivos', RESEED, 0);
IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Zonas') AND last_value IS NOT NULL)
    DBCC CHECKIDENT ('dbo.Zonas', RESEED, 0);
GO

-- Zonas
INSERT dbo.Zonas (Nombre, Descripcion, ContactoEmail) VALUES
    (N'Recepcion',          N'Entrada y zona de atencion al publico, planta baja',  N'recepcion@miniscada.example'),
    (N'Sala de servidores', N'Centro de proceso de datos, sotano',                  N'sistemas@miniscada.example'),
    (N'Oficinas',           N'Oficinas diafanas de la primera planta',              N'oficinas@miniscada.example'),
    (N'Almacen',            N'Nave trasera con almacen y bomba de achique',         N'almacen@miniscada.example');
GO

-- Dispositivos
INSERT dbo.Dispositivos (ZonaId, Nombre, Modelo, Estado, FechaAlta)
SELECT z.ZonaId, v.Nombre, v.Modelo, 'activo', v.FechaAlta
FROM (VALUES
    (N'Recepcion',          N'Nodo-Recepcion-1',    N'ESP32-S3',            CAST('2026-06-01' AS date)),
    (N'Recepcion',          N'Contador-Energia-Rec',N'Medidor monofasico',  CAST('2026-06-01' AS date)),
    (N'Sala de servidores', N'Nodo-CPD-1',          N'ESP32-S3',            CAST('2026-06-01' AS date)),
    (N'Sala de servidores', N'Nodo-CPD-2',          N'ESP32-C3',            CAST('2026-06-01' AS date)),
    (N'Oficinas',           N'Nodo-Oficina-1',      N'ESP32',               CAST('2026-06-02' AS date)),
    (N'Oficinas',           N'Nodo-Oficina-2',      N'ESP32',               CAST('2026-06-02' AS date)),
    (N'Almacen',            N'Nodo-Almacen-1',      N'ESP32-C3',            CAST('2026-06-03' AS date)),
    (N'Almacen',            N'Bomba-Almacen-1',     N'Controlador de bomba',CAST('2026-06-03' AS date))
) AS v (Zona, Nombre, Modelo, FechaAlta)
JOIN dbo.Zonas z ON z.Nombre = v.Zona;
GO

-- Sensores. El perfil (Base, Amplitud, Ruido) solo sirve para generar las
-- lecturas: valor = Base + Amplitud * ciclo diario + Ruido * variacion.
CREATE TABLE #Perfil (
    SensorId  INT NULL,
    Disp      NVARCHAR(100) NOT NULL,
    Nombre    NVARCHAR(100) NOT NULL,
    Tipo      NVARCHAR(30) NOT NULL,
    Unidad    NVARCHAR(15) NOT NULL,
    MinNormal DECIMAL(10,2) NOT NULL,
    MaxNormal DECIMAL(10,2) NOT NULL,
    Base      DECIMAL(10,2) NOT NULL,
    Amplitud  DECIMAL(10,2) NOT NULL,
    Ruido     DECIMAL(10,2) NOT NULL
);

INSERT #Perfil (Disp, Nombre, Tipo, Unidad, MinNormal, MaxNormal, Base, Amplitud, Ruido) VALUES
    (N'Nodo-Recepcion-1',     N'Temperatura', 'temperatura', N'C',     18.00,  26.00,  22.00,   1.80,  0.30),
    (N'Nodo-Recepcion-1',     N'Humedad',     'humedad',     N'%',     30.00,  60.00,  45.00,   5.00,  1.50),
    (N'Nodo-Recepcion-1',     N'CO2',         'co2',         N'ppm',  400.00,1000.00, 620.00, 180.00, 20.00),
    (N'Contador-Energia-Rec', N'Consumo',     'consumo',     N'kW',     0.20,   3.00,   1.60,   0.90,  0.10),
    (N'Nodo-CPD-1',           N'Temperatura', 'temperatura', N'C',     18.00,  27.00,  22.00,   1.00,  0.30),
    (N'Nodo-CPD-1',           N'Humedad',     'humedad',     N'%',     40.00,  60.00,  48.00,   2.00,  1.00),
    (N'Nodo-CPD-2',           N'Temperatura', 'temperatura', N'C',     18.00,  27.00,  23.00,   1.00,  0.30),
    (N'Nodo-CPD-2',           N'Consumo',     'consumo',     N'kW',     2.00,   8.00,   5.00,   0.80,  0.20),
    (N'Nodo-Oficina-1',       N'Temperatura', 'temperatura', N'C',     18.00,  26.00,  22.00,   1.80,  0.30),
    (N'Nodo-Oficina-1',       N'Humedad',     'humedad',     N'%',     30.00,  60.00,  42.00,   5.00,  1.50),
    (N'Nodo-Oficina-1',       N'CO2',         'co2',         N'ppm',  400.00,1000.00, 620.00, 180.00, 20.00),
    (N'Nodo-Oficina-2',       N'Temperatura', 'temperatura', N'C',     18.00,  26.00,  22.00,   1.50,  0.30),
    (N'Nodo-Oficina-2',       N'CO2',         'co2',         N'ppm',  400.00,1000.00, 620.00, 180.00, 20.00),
    (N'Nodo-Oficina-2',       N'Consumo',     'consumo',     N'kW',     1.00,   6.00,   3.20,   1.40,  0.20),
    (N'Nodo-Almacen-1',       N'Temperatura', 'temperatura', N'C',      8.00,  30.00,  17.00,   6.00,  0.50),
    (N'Nodo-Almacen-1',       N'Humedad',     'humedad',     N'%',     30.00,  75.00,  55.00,   6.00,  2.00),
    (N'Bomba-Almacen-1',      N'Presion',     'presion',     N'bar',    1.50,   4.00,   2.80,   0.30,  0.05),
    (N'Bomba-Almacen-1',      N'Caudal',      'caudal',      N'l/min', 10.00,  60.00,  35.00,   8.00,  1.50);

INSERT dbo.Sensores (DispositivoId, Nombre, Tipo, Unidad, MinNormal, MaxNormal)
SELECT d.DispositivoId, p.Nombre, p.Tipo, p.Unidad, p.MinNormal, p.MaxNormal
FROM #Perfil p
JOIN dbo.Dispositivos d ON d.Nombre = p.Disp;

UPDATE p SET SensorId = s.SensorId
FROM #Perfil p
JOIN dbo.Dispositivos d ON d.Nombre = p.Disp
JOIN dbo.Sensores s ON s.DispositivoId = d.DispositivoId AND s.Nombre = p.Nombre;
GO

-- Usuarios y zonas que ven (se usan en la fase de seguridad)
INSERT dbo.UsuariosZona (NombreUsuario, ZonaId)
SELECT v.Usuario, z.ZonaId
FROM (VALUES
    (N'tecnico_cpd',       N'Sala de servidores'),
    (N'tecnico_oficinas',  N'Recepcion'),
    (N'tecnico_oficinas',  N'Oficinas'),
    (N'tecnico_almacen',   N'Almacen')
) AS v (Usuario, Zona)
JOIN dbo.Zonas z ON z.Nombre = v.Zona;
GO

-- Lecturas: 28.800 por sensor (una cada 5 minutos durante 100 dias).
-- Ciclo diario con maximo a las 15:00 y variacion repetible.
DECLARE @Inicio DATETIME2(0) = '2026-06-20T00:00:00';

INSERT dbo.Lecturas (SensorId, FechaHora, Valor)
SELECT p.SensorId,
       DATEADD(MINUTE, g.value * 5, @Inicio),
       CAST(p.Base
            + p.Amplitud * SIN(2 * PI() * (((g.value * 5) % 1440) / 60.0 - 9) / 24.0)
            + p.Ruido * (ABS(CAST(SUBSTRING(HASHBYTES('MD5', CONCAT(p.SensorId, '-', g.value)), 1, 4) AS INT) % 2001) / 1000.0 - 1.0)
            AS DECIMAL(10,2))
FROM #Perfil p
CROSS JOIN GENERATE_SERIES(0, 28799) AS g
ORDER BY p.SensorId, g.value;
GO

-- ANOMALIAS A PROPOSITO ------------------------------------------------------

-- 1. CO2 plano: el sensor de la oficina 2 se queda en 412 ppm toda la manana.
--    El valor esta dentro del rango normal; lo raro es que no se mueve.
UPDATE l SET Valor = 412.00
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Oficina-2' AND s.Nombre = N'CO2'
  AND l.FechaHora >= '2026-08-10T03:00:00' AND l.FechaHora < '2026-08-10T15:00:00';

-- 2. Lo mismo en la oficina 1, a 455 ppm, el 18 de septiembre.
UPDATE l SET Valor = 455.00
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Oficina-1' AND s.Nombre = N'CO2'
  AND l.FechaHora >= '2026-09-18T08:00:00' AND l.FechaHora < '2026-09-18T14:00:00';

-- 3. Sala de servidores: la temperatura sube 9 grados por un fallo de refrigeracion.
UPDATE l SET Valor = l.Valor + 9
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-CPD-1' AND s.Nombre = N'Temperatura'
  AND l.FechaHora >= '2026-07-15T12:00:00' AND l.FechaHora < '2026-07-15T18:00:00';

-- 4. Sala de servidores otra vez, de madrugada tras un corte de luz (+7 grados).
UPDATE l SET Valor = l.Valor + 7
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-CPD-1' AND s.Nombre = N'Temperatura'
  AND l.FechaHora >= '2026-08-30T02:30:00' AND l.FechaHora < '2026-08-30T05:30:00';

-- 5. Almacen: la humedad se dispara por una fuga de agua (maximo 98 %).
UPDATE l SET Valor = LEAST(l.Valor + 38, 98.00)
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Almacen-1' AND s.Nombre = N'Humedad'
  AND l.FechaHora >= '2026-09-02T05:00:00' AND l.FechaHora < '2026-09-02T10:00:00';

-- 6. Bomba: se pierde el cebado y caen la presion y el caudal.
UPDATE l SET Valor = l.Valor * 0.15
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Bomba-Almacen-1' AND s.Nombre = N'Presion'
  AND l.FechaHora >= '2026-08-20T10:00:00' AND l.FechaHora < '2026-08-20T14:00:00';

UPDATE l SET Valor = l.Valor * 0.08
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Bomba-Almacen-1' AND s.Nombre = N'Caudal'
  AND l.FechaHora >= '2026-08-20T10:00:00' AND l.FechaHora < '2026-08-20T14:00:00';

-- 7. Sala de servidores: el consumo se duplica de madrugada.
UPDATE l SET Valor = l.Valor * 2
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-CPD-2' AND s.Nombre = N'Consumo'
  AND l.FechaHora >= '2026-09-10T01:00:00' AND l.FechaHora < '2026-09-10T06:00:00';

-- 8. Recepcion: el nodo pierde la conexion cinco horas, faltan lecturas.
DELETE l
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Recepcion-1'
  AND l.FechaHora >= '2026-07-28T06:00:00' AND l.FechaHora < '2026-07-28T11:00:00';

-- 9. Almacen: de noche la temperatura baja a unos 5 grados (puerta abierta).
UPDATE l SET Valor = l.Valor * 0.4
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Almacen-1' AND s.Nombre = N'Temperatura'
  AND l.FechaHora >= '2026-09-24T22:00:00' AND l.FechaHora < '2026-09-25T05:00:00';

-- 10. Oficina 1: por la tarde la temperatura sube 4 grados.
UPDATE l SET Valor = l.Valor + 4
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Oficina-1' AND s.Nombre = N'Temperatura'
  AND l.FechaHora >= '2026-09-25T14:00:00' AND l.FechaHora < '2026-09-25T17:00:00';

-- 11. Oficina 2: el consumo sube un 70 % por la manana.
UPDATE l SET Valor = l.Valor * 1.7
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE d.Nombre = N'Nodo-Oficina-2' AND s.Nombre = N'Consumo'
  AND l.FechaHora >= '2026-09-26T09:00:00' AND l.FechaHora < '2026-09-26T13:00:00';
GO

-- Mensaje JSON original de cada lectura (se genera al final para que coincida
-- con el valor definitivo, anomalias incluidas)
UPDATE dbo.Lecturas
SET PayloadJson = CONCAT('{"sensor":', SensorId,
                         ',"valor":', CONVERT(varchar(20), Valor),
                         ',"bateria":', 60 + ABS(CAST(SUBSTRING(HASHBYTES('MD5', CONCAT('b', LecturaId)), 1, 4) AS INT) % 41),
                         ',"rssi":', -40 - ABS(CAST(SUBSTRING(HASHBYTES('MD5', CONCAT('r', LecturaId)), 1, 4) AS INT) % 41),
                         '}');
GO

-- Alarmas
INSERT dbo.Alarmas (SensorId, FechaHora, Severidad, Descripcion, Estado)
SELECT s.SensorId, v.FechaHora, v.Severidad, v.Descripcion, v.Estado
FROM (VALUES
    (N'Nodo-Oficina-2',   N'CO2',         CAST('2026-08-10T09:05:00' AS datetime2(0)), 'media',   N'El sensor de CO2 marca siempre 412 ppm desde hace horas, la grafica esta plana y no sigue la ocupacion de la sala', 'cerrada'),
    (N'Nodo-Oficina-1',   N'CO2',         CAST('2026-09-18T11:20:00' AS datetime2(0)), 'media',   N'Lecturas de CO2 constantes en 455 ppm durante seis horas, el valor no cambia aunque la oficina esta llena', 'cerrada'),
    (N'Nodo-CPD-1',       N'Temperatura', CAST('2026-07-15T14:20:00' AS datetime2(0)), 'alta',    N'La temperatura de la sala de servidores supera los 30 grados y la refrigeracion no esta enfriando', 'cerrada'),
    (N'Nodo-CPD-1',       N'Temperatura', CAST('2026-08-30T03:10:00' AS datetime2(0)), 'alta',    N'Subida de temperatura en la sala de servidores de madrugada, casi 30 grados, el aire acondicionado no arranco tras un corte de luz', 'cerrada'),
    (N'Nodo-Almacen-1',   N'Humedad',     CAST('2026-09-02T07:40:00' AS datetime2(0)), 'alta',    N'Humedad por encima del 90 por ciento en el almacen, posible fuga de agua cerca del sensor', 'cerrada'),
    (N'Bomba-Almacen-1',  N'Presion',     CAST('2026-08-20T11:15:00' AS datetime2(0)), 'critica', N'La presion de la bomba ha caido a 0,4 bar y casi no hay caudal', 'cerrada'),
    (N'Nodo-CPD-2',       N'Consumo',     CAST('2026-09-10T02:05:00' AS datetime2(0)), 'media',   N'Consumo electrico del rack el doble de lo normal durante la noche', 'cerrada'),
    (N'Nodo-Recepcion-1', N'Temperatura', CAST('2026-07-28T06:30:00' AS datetime2(0)), 'media',   N'El nodo de recepcion no envia lecturas desde las seis de la manana', 'cerrada'),
    (N'Nodo-Almacen-1',   N'Temperatura', CAST('2026-09-24T23:10:00' AS datetime2(0)), 'media',   N'La temperatura del almacen baja de 8 grados por la noche, posible puerta del muelle abierta', 'en curso'),
    (N'Nodo-Oficina-1',   N'Temperatura', CAST('2026-09-25T15:30:00' AS datetime2(0)), 'baja',    N'Temperatura de la oficina uno por encima de 26 grados por la tarde', 'abierta'),
    (N'Nodo-Oficina-2',   N'Consumo',     CAST('2026-09-26T10:15:00' AS datetime2(0)), 'media',   N'El consumo de la oficina dos esta muy por encima de lo habitual a media manana', 'abierta')
) AS v (Disp, Sensor, FechaHora, Severidad, Descripcion, Estado)
JOIN dbo.Dispositivos d ON d.Nombre = v.Disp
JOIN dbo.Sensores s ON s.DispositivoId = d.DispositivoId AND s.Nombre = v.Sensor;
GO

-- Incidencias: como se resolvio cada alarma (las dos abiertas no tienen todavia)
INSERT dbo.Incidencias (AlarmaId, Responsable, FechaApertura, FechaCierre, Causa, Solucion)
SELECT a.AlarmaId, v.Responsable, v.Apertura, v.Cierre, v.Causa, v.Solucion
FROM (VALUES
    (N'Nodo-Oficina-2',   N'CO2',         CAST('2026-08-10T09:05:00' AS datetime2(0)), N'tecnico_oficinas', CAST('2026-08-10T09:30:00' AS datetime2(0)), CAST('2026-08-10T12:15:00' AS datetime2(0)),
        N'Sensor de CO2 descalibrado y con polvo acumulado en la entrada de aire',
        N'Se limpio la entrada de aire y se recalibro el sensor al aire libre a 420 ppm. Vuelve a seguir la ocupacion de la sala.'),
    (N'Nodo-Oficina-1',   N'CO2',         CAST('2026-09-18T11:20:00' AS datetime2(0)), N'tecnico_oficinas', CAST('2026-09-18T11:45:00' AS datetime2(0)), CAST('2026-09-18T13:10:00' AS datetime2(0)),
        N'Cable del sensor flojo en el conector, el nodo repetia el ultimo valor leido',
        N'Se reapreto el conector, se sustituyo el cable y se reinicio el nodo.'),
    (N'Nodo-CPD-1',       N'Temperatura', CAST('2026-07-15T14:20:00' AS datetime2(0)), N'tecnico_cpd',      CAST('2026-07-15T14:40:00' AS datetime2(0)), CAST('2026-07-15T18:30:00' AS datetime2(0)),
        N'Filtro de la unidad de aire acondicionado obstruido y ventilador del condensador parado',
        N'Se limpio el filtro y se reemplazo el motor del ventilador del condensador.'),
    (N'Nodo-CPD-1',       N'Temperatura', CAST('2026-08-30T03:10:00' AS datetime2(0)), N'tecnico_cpd',      CAST('2026-08-30T03:35:00' AS datetime2(0)), CAST('2026-08-30T06:00:00' AS datetime2(0)),
        N'Corte de luz breve y la unidad de aire acondicionado no rearranco sola',
        N'Se rearmo el termico y se configuro el rearranque automatico de la unidad.'),
    (N'Nodo-Almacen-1',   N'Humedad',     CAST('2026-09-02T07:40:00' AS datetime2(0)), N'tecnico_almacen',  CAST('2026-09-02T08:00:00' AS datetime2(0)), CAST('2026-09-02T11:30:00' AS datetime2(0)),
        N'Fuga en una tuberia de la zona de lavado, junto al sensor',
        N'Se reparo la junta de la tuberia y se seco la zona con deshumidificador.'),
    (N'Bomba-Almacen-1',  N'Presion',     CAST('2026-08-20T11:15:00' AS datetime2(0)), N'tecnico_almacen',  CAST('2026-08-20T11:30:00' AS datetime2(0)), CAST('2026-08-20T14:20:00' AS datetime2(0)),
        N'La bomba perdio el cebado porque se vacio el deposito de entrada',
        N'Se relleno el deposito y se volvio a cebar la bomba. Se anadio un aviso de nivel bajo.'),
    (N'Nodo-CPD-2',       N'Consumo',     CAST('2026-09-10T02:05:00' AS datetime2(0)), N'tecnico_cpd',      CAST('2026-09-10T02:30:00' AS datetime2(0)), CAST('2026-09-10T06:10:00' AS datetime2(0)),
        N'Un servidor de pruebas quedo en bucle de calculo tras una actualizacion',
        N'Se reinicio el servidor y se corrigio la tarea programada que lo lanzaba.'),
    (N'Nodo-Recepcion-1', N'Temperatura', CAST('2026-07-28T06:30:00' AS datetime2(0)), N'tecnico_oficinas', CAST('2026-07-28T07:00:00' AS datetime2(0)), CAST('2026-07-28T11:05:00' AS datetime2(0)),
        N'El router wifi se reinicio y el nodo no volvio a conectarse',
        N'Se reinicio el nodo y se fijo su direccion IP en el router.'),
    (N'Nodo-Almacen-1',   N'Temperatura', CAST('2026-09-24T23:10:00' AS datetime2(0)), N'tecnico_almacen',  CAST('2026-09-25T07:30:00' AS datetime2(0)), CAST(NULL AS datetime2(0)),
        CAST(NULL AS nvarchar(500)),
        CAST(NULL AS nvarchar(1000)))
) AS v (Disp, Sensor, FechaAlarma, Responsable, Apertura, Cierre, Causa, Solucion)
JOIN dbo.Dispositivos d ON d.Nombre = v.Disp
JOIN dbo.Sensores s ON s.DispositivoId = d.DispositivoId AND s.Nombre = v.Sensor
JOIN dbo.Alarmas a ON a.SensorId = s.SensorId AND a.FechaHora = v.FechaAlarma;
GO

DROP TABLE #Perfil;
GO

-- COMPROBACION ---------------------------------------------------------------

-- Filas por tabla (Lecturas debe pasar de las 500.000)
SELECT 'Zonas' AS Tabla, COUNT(*) AS Filas FROM dbo.Zonas
UNION ALL SELECT 'Dispositivos', COUNT(*) FROM dbo.Dispositivos
UNION ALL SELECT 'Sensores', COUNT(*) FROM dbo.Sensores
UNION ALL SELECT 'Lecturas', COUNT(*) FROM dbo.Lecturas
UNION ALL SELECT 'Alarmas', COUNT(*) FROM dbo.Alarmas
UNION ALL SELECT 'Incidencias', COUNT(*) FROM dbo.Incidencias
UNION ALL SELECT 'UsuariosZona', COUNT(*) FROM dbo.UsuariosZona;
GO

-- Lecturas fuera de su rango normal por sensor. Salen las anomalias de subida
-- o bajada; las de CO2 plano no aparecen aqui porque su valor esta dentro del rango.
SELECT d.Nombre AS Dispositivo, s.Nombre AS Sensor, COUNT(*) AS LecturasFueraDeRango
FROM dbo.Lecturas l
JOIN dbo.Sensores s ON s.SensorId = l.SensorId
JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
WHERE l.Valor < s.MinNormal OR l.Valor > s.MaxNormal
GROUP BY d.Nombre, s.Nombre
ORDER BY LecturasFueraDeRango DESC;
GO

-- Una lectura de ejemplo y las alarmas (para comprobar que el JSON y los textos se ven bien)
SELECT TOP 3 LecturaId, SensorId, FechaHora, Valor, PayloadJson FROM dbo.Lecturas ORDER BY LecturaId;
SELECT AlarmaId, FechaHora, Severidad, Estado, Descripcion FROM dbo.Alarmas ORDER BY AlarmaId;
GO
