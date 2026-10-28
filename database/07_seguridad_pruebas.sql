-- Mini-SCADA: pruebas de la seguridad.
-- Se ejecuta bloque a bloque (o entero con F5) despues de 06_seguridad.sql.
-- Cada bloque cambia de usuario con EXECUTE AS y vuelve con REVERT. Los que
-- intentan modificar datos van dentro de una transaccion que se deshace.

USE MiniScada;
GO

-- PRUEBA 1: la misma consulta con el administrador y con un tecnico de zona ----
-- El administrador ve las 4 zonas y las 11 alarmas. El tecnico de la sala de
-- servidores solo ve su zona y sus 3 alarmas.

EXECUTE AS USER = 'admin_scada';
SELECT USER_NAME() AS Usuario,
       (SELECT COUNT(*) FROM dbo.Zonas) AS Zonas,
       (SELECT COUNT(*) FROM dbo.Sensores) AS Sensores,
       (SELECT COUNT(*) FROM dbo.Alarmas) AS Alarmas,
       (SELECT COUNT(*) FROM dbo.Incidencias) AS Incidencias;
SELECT AlarmaId, Zona, Sensor, Severidad, Estado FROM dbo.vw_AlarmasConIncidencia ORDER BY AlarmaId;
REVERT;
GO

EXECUTE AS USER = 'tecnico_cpd';
SELECT USER_NAME() AS Usuario,
       (SELECT COUNT(*) FROM dbo.Zonas) AS Zonas,
       (SELECT COUNT(*) FROM dbo.Sensores) AS Sensores,
       (SELECT COUNT(*) FROM dbo.Alarmas) AS Alarmas,
       (SELECT COUNT(*) FROM dbo.Incidencias) AS Incidencias;
SELECT AlarmaId, Zona, Sensor, Severidad, Estado FROM dbo.vw_AlarmasConIncidencia ORDER BY AlarmaId;
REVERT;
GO

-- PRUEBA 2: enmascarado del email de contacto --------------------------------
-- El administrador lo ve completo. El tecnico de oficinas, que ve dos zonas,
-- lo ve enmascarado.

EXECUTE AS USER = 'admin_scada';
SELECT USER_NAME() AS Usuario, ZonaId, Nombre, ContactoEmail FROM dbo.Zonas ORDER BY ZonaId;
REVERT;
GO

EXECUTE AS USER = 'tecnico_oficinas';
SELECT USER_NAME() AS Usuario, ZonaId, Nombre, ContactoEmail FROM dbo.Zonas ORDER BY ZonaId;
REVERT;
GO

-- PRUEBA 3: lo que el tecnico de la sala de servidores NO puede hacer ---------

DECLARE @SensorAlmacen INT = (SELECT s.SensorId FROM dbo.Sensores s
                              JOIN dbo.Dispositivos d ON d.DispositivoId = s.DispositivoId
                              WHERE d.Nombre = N'Nodo-Almacen-1' AND s.Nombre = N'Temperatura');
DECLARE @Intentos TABLE (Id INT IDENTITY(1,1), Intento NVARCHAR(80), Resultado NVARCHAR(160));
DECLARE @n INT, @Alarma INT;

BEGIN TRAN;
EXECUTE AS USER = 'tecnico_cpd';

BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.Lecturas;
    INSERT @Intentos (Intento, Resultado) VALUES (N'Leer la tabla Lecturas', N'PERMITIDO (' + CAST(@n AS NVARCHAR(20)) + N' filas)');
END TRY
BEGIN CATCH
    INSERT @Intentos (Intento, Resultado) VALUES (N'Leer la tabla Lecturas', N'DENEGADO, error ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)));
END CATCH;

BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.vw_LecturasVisibles;
    INSERT @Intentos (Intento, Resultado) VALUES (N'Leer lecturas con la vista vw_LecturasVisibles', N'PERMITIDO (' + CAST(@n AS NVARCHAR(20)) + N' filas, solo de su zona)');
END TRY
BEGIN CATCH
    INSERT @Intentos (Intento, Resultado) VALUES (N'Leer lecturas con la vista vw_LecturasVisibles', N'DENEGADO, error ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)));
END CATCH;

BEGIN TRY
    DELETE FROM dbo.Alarmas;
    INSERT @Intentos (Intento, Resultado) VALUES (N'Borrar alarmas', N'PERMITIDO');
END TRY
BEGIN CATCH
    INSERT @Intentos (Intento, Resultado) VALUES (N'Borrar alarmas', N'DENEGADO, error ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)));
END CATCH;

BEGIN TRY
    UPDATE dbo.Zonas SET Descripcion = N'cambiada';
    INSERT @Intentos (Intento, Resultado) VALUES (N'Modificar zonas', N'PERMITIDO');
END TRY
BEGIN CATCH
    INSERT @Intentos (Intento, Resultado) VALUES (N'Modificar zonas', N'DENEGADO, error ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)));
END CATCH;

BEGIN TRY
    EXEC dbo.usp_RegistrarAlarma @SensorId = @SensorAlmacen, @Severidad = 'baja',
         @Descripcion = N'Prueba en una zona que no es la suya', @AlarmaId = @Alarma OUTPUT;
    INSERT @Intentos (Intento, Resultado) VALUES (N'Crear una alarma en la zona del almacen', N'PERMITIDO');
END TRY
BEGIN CATCH
    INSERT @Intentos (Intento, Resultado) VALUES (N'Crear una alarma en la zona del almacen', N'DENEGADO, error ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)));
END CATCH;

REVERT;
ROLLBACK;

SELECT Intento, Resultado FROM @Intentos ORDER BY Id;
GO

-- Despues de las pruebas siguen las 11 alarmas de antes
SELECT COUNT(*) AS Alarmas FROM dbo.Alarmas;
GO
