-- Comprobar que SQL Server 2025 puede generar embeddings con Ollama.
-- Necesita Ollama y nginx en marcha (ver ollama-https-proxy.md).
-- Se ejecuta bloque a bloque, en orden.

-- Versión de SQL Server
SELECT @@VERSION AS Version;
GO

-- Permitir llamadas a endpoints REST externos
EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- Llamada directa al proxy local, sin modelo. La respuesta sale por el parámetro
-- @response, así que hay que sacarla con un SELECT. Debe empezar por "code":200
DECLARE @ret INT, @response NVARCHAR(MAX);
EXEC @ret = sp_invoke_external_rest_endpoint
    @url      = N'https://localhost:11435/api/embed',
    @method   = 'POST',
    @headers  = N'{"Content-Type":"application/json"}',
    @payload  = N'{"model":"nomic-embed-text","input":"prueba"}',
    @response = @response OUTPUT;
SELECT @ret AS CodigoRetorno, LEFT(@response, 400) AS Respuesta;
GO

-- Base de datos del proyecto
IF DB_ID('MiniScada') IS NULL CREATE DATABASE MiniScada;
GO
USE MiniScada;
GO

-- Modelo externo (vive dentro de la base de datos)
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'ModeloEmbeddings')
    DROP EXTERNAL MODEL ModeloEmbeddings;
GO

CREATE EXTERNAL MODEL ModeloEmbeddings
WITH (
    LOCATION   = 'https://localhost:11435/api/embed',
    API_FORMAT = 'Ollama',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'nomic-embed-text'
);
GO

SELECT name, location, api_format, model FROM sys.external_models;
GO

-- Vector de prueba
SELECT AI_GENERATE_EMBEDDINGS(
    N'sensor de CO2 con lecturas planas' USE MODEL ModeloEmbeddings
) AS Embedding;
GO

-- Si la llamada directa falla, probar contra una URL HTTPS pública para ver
-- si el problema es de la función o de la conexión con el proxy local:
-- DECLARE @ret INT, @response NVARCHAR(MAX);
-- EXEC @ret = sp_invoke_external_rest_endpoint @url = N'https://httpbin.org/get', @method = 'GET', @response = @response OUTPUT;
-- SELECT @ret AS CodigoRetorno, LEFT(@response, 400) AS Respuesta;
