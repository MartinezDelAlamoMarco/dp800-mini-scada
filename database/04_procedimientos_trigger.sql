-- Mini-SCADA: dos procedimientos y un trigger.
-- Se ejecuta entero con F5 despues de 03_vistas_funcion.sql. Se puede repetir.
-- Las pruebas del final se hacen dentro de una transaccion que se deshace, asi
-- que no cambian los datos (aunque sus numeros de identidad se gastan).

USE MiniScada;
GO

-- Procedimiento 1: registrar una alarma nueva y devolver su identificador.
-- Los nombres empiezan por usp_ y no por sp_, que esta reservado para el sistema.
CREATE OR ALTER PROCEDURE dbo.usp_RegistrarAlarma
    @SensorId    INT,
    @Severidad   NVARCHAR(10),
    @Descripcion NVARCHAR(500),
    @FechaHora   DATETIME2(0) = NULL,   -- si no se indica, se usa la hora actual
    @AlarmaId    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Sensores WHERE SensorId = @SensorId)
        THROW 50001, N'El sensor indicado no existe.', 1;

    IF @Severidad NOT IN ('baja', 'media', 'alta', 'critica')
        THROW 50002, N'Severidad no valida: usa baja, media, alta o critica.', 1;

    INSERT dbo.Alarmas (SensorId, FechaHora, Severidad, Descripcion)
    VALUES (@SensorId, ISNULL(@FechaHora, SYSDATETIME()), @Severidad, @Descripcion);

    SET @AlarmaId = SCOPE_IDENTITY();
END;
GO

-- Procedimiento 2: cerrar la incidencia de una alarma. Si la alarma ya tenia una
-- incidencia abierta la completa, y si no la tenia crea una ya cerrada. El cambio
-- de estado de la alarma lo hace el trigger.
CREATE OR ALTER PROCEDURE dbo.usp_CerrarIncidencia
    @AlarmaId    INT,
    @Responsable NVARCHAR(100),
    @Causa       NVARCHAR(500),
    @Solucion    NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Alarmas WHERE AlarmaId = @AlarmaId)
        THROW 50003, N'La alarma indicada no existe.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Alarmas WHERE AlarmaId = @AlarmaId AND Estado = 'cerrada')
        THROW 50004, N'La alarma ya esta cerrada.', 1;

    DECLARE @Ahora DATETIME2(0) = SYSDATETIME();

    IF EXISTS (SELECT 1 FROM dbo.Incidencias WHERE AlarmaId = @AlarmaId AND FechaCierre IS NULL)
        UPDATE dbo.Incidencias
        SET Responsable = @Responsable,
            FechaCierre = @Ahora,
            Causa       = @Causa,
            Solucion    = @Solucion
        WHERE AlarmaId = @AlarmaId AND FechaCierre IS NULL;
    ELSE
        INSERT dbo.Incidencias (AlarmaId, Responsable, FechaApertura, FechaCierre, Causa, Solucion)
        VALUES (@AlarmaId, @Responsable, @Ahora, @Ahora, @Causa, @Solucion);
END;
GO

-- Trigger: mantiene el estado de la alarma segun su incidencia.
-- Incidencia abierta -> la alarma pasa a "en curso" (si estaba abierta).
-- Incidencia con fecha de cierre -> la alarma pasa a "cerrada".
-- Funciona tambien cuando se insertan o actualizan varias filas a la vez.
CREATE OR ALTER TRIGGER dbo.trg_Incidencias_EstadoAlarma
ON dbo.Incidencias
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE a
    SET Estado = 'cerrada'
    FROM dbo.Alarmas a
    JOIN inserted i ON i.AlarmaId = a.AlarmaId
    WHERE i.FechaCierre IS NOT NULL AND a.Estado <> 'cerrada';

    UPDATE a
    SET Estado = 'en curso'
    FROM dbo.Alarmas a
    JOIN inserted i ON i.AlarmaId = a.AlarmaId
    WHERE i.FechaCierre IS NULL AND a.Estado = 'abierta';
END;
GO

-- COMPROBACION ---------------------------------------------------------------

-- Prueba 1: los dos errores que controla el procedimiento de registrar alarmas
DECLARE @Sensor INT = (SELECT s.SensorId FROM dbo.Sensores s
                       JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                       WHERE d.Nombre = N'Nodo-Oficina-2' AND s.Nombre = N'CO2');
DECLARE @Id INT;

BEGIN TRY
    EXEC dbo.usp_RegistrarAlarma @SensorId = -1, @Severidad = 'media',
         @Descripcion = N'Prueba con sensor inexistente', @AlarmaId = @Id OUTPUT;
END TRY
BEGIN CATCH
    SELECT 'Sensor inexistente' AS Prueba, ERROR_NUMBER() AS Numero, ERROR_MESSAGE() AS Mensaje;
END CATCH;

BEGIN TRY
    EXEC dbo.usp_RegistrarAlarma @SensorId = @Sensor, @Severidad = 'muy alta',
         @Descripcion = N'Prueba con severidad incorrecta', @AlarmaId = @Id OUTPUT;
END TRY
BEGIN CATCH
    SELECT 'Severidad incorrecta' AS Prueba, ERROR_NUMBER() AS Numero, ERROR_MESSAGE() AS Mensaje;
END CATCH;
GO

-- Prueba 2: ciclo completo de una alarma (se deshace al final)
BEGIN TRAN;

DECLARE @Sensor INT = (SELECT s.SensorId FROM dbo.Sensores s
                       JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                       WHERE d.Nombre = N'Nodo-Oficina-2' AND s.Nombre = N'CO2');
DECLARE @Alarma INT;
DECLARE @Estados TABLE (Paso NVARCHAR(60), EstadoAlarma NVARCHAR(15));

EXEC dbo.usp_RegistrarAlarma @SensorId = @Sensor, @Severidad = 'media',
     @Descripcion = N'Prueba del ciclo de vida de una alarma', @AlarmaId = @Alarma OUTPUT;
INSERT @Estados SELECT N'1. Alarma recien registrada', Estado FROM dbo.Alarmas WHERE AlarmaId = @Alarma;

INSERT dbo.Incidencias (AlarmaId, Responsable, FechaApertura)
VALUES (@Alarma, N'tecnico_oficinas', SYSDATETIME());
INSERT @Estados SELECT N'2. Se abre una incidencia', Estado FROM dbo.Alarmas WHERE AlarmaId = @Alarma;

EXEC dbo.usp_CerrarIncidencia @AlarmaId = @Alarma, @Responsable = N'tecnico_oficinas',
     @Causa = N'Prueba', @Solucion = N'Prueba';
INSERT @Estados SELECT N'3. Se cierra la incidencia', Estado FROM dbo.Alarmas WHERE AlarmaId = @Alarma;

SELECT Paso, EstadoAlarma FROM @Estados ORDER BY Paso;

ROLLBACK;
GO

-- Despues de las pruebas siguen las 11 alarmas y 9 incidencias de antes
SELECT (SELECT COUNT(*) FROM dbo.Alarmas) AS Alarmas,
       (SELECT COUNT(*) FROM dbo.Incidencias) AS Incidencias;
GO
