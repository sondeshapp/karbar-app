CREATE TABLE IF NOT EXISTS catalog_entities (
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('product', 'customer')),
    entity_id UUID NOT NULL,
    revision BIGINT NOT NULL CHECK (revision > 0),
    payload JSONB NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    updated_by UUID NOT NULL REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (shop_id, entity_type, entity_id)
);

CREATE TABLE IF NOT EXISTS catalog_changes (
    cursor BIGSERIAL PRIMARY KEY,
    shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('product', 'customer')),
    entity_id UUID NOT NULL,
    mutation_id UUID NOT NULL,
    base_revision BIGINT NOT NULL CHECK (base_revision >= 0),
    revision BIGINT NOT NULL CHECK (revision > 0),
    payload JSONB NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    changed_by UUID NOT NULL REFERENCES users(id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (shop_id, mutation_id),
    UNIQUE (shop_id, entity_type, entity_id, revision)
);

CREATE INDEX IF NOT EXISTS catalog_changes_shop_cursor_idx
    ON catalog_changes (shop_id, cursor);
