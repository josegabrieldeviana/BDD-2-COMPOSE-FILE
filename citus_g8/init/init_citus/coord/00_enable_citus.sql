-- Conectarse a la base principal
\c coorddb;

-- Habilitar extensión Citus
CREATE EXTENSION IF NOT EXISTS citus;

-- Verificar que se habilitó correctamente
\dx
