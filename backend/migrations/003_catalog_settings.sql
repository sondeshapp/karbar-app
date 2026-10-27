ALTER TABLE catalog_entities
    DROP CONSTRAINT IF EXISTS catalog_entities_entity_type_check;
ALTER TABLE catalog_entities
    ADD CONSTRAINT catalog_entities_entity_type_check
    CHECK (entity_type IN ('product', 'customer', 'settings'));

ALTER TABLE catalog_changes
    DROP CONSTRAINT IF EXISTS catalog_changes_entity_type_check;
ALTER TABLE catalog_changes
    ADD CONSTRAINT catalog_changes_entity_type_check
    CHECK (entity_type IN ('product', 'customer', 'settings'));
