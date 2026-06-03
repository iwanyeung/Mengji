export const SCHEMA_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(64) PRIMARY KEY,
    created_at VARCHAR(32) NOT NULL,
    updated_at VARCHAR(32) NOT NULL,
    auth_provider VARCHAR(16) NOT NULL,
    device_id VARCHAR(128),
    apple_id VARCHAR(128),
    wechat_id VARCHAR(128),
    age_range VARCHAR(16),
    gender_identity VARCHAR(32),
    color_preference VARCHAR(16)
  )`,

  `CREATE TABLE IF NOT EXISTS dreams (
    id VARCHAR(64) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    created_at VARCHAR(32) NOT NULL,
    updated_at VARCHAR(32) NOT NULL,
    occurred_at VARCHAR(32) NOT NULL,
    source VARCHAR(16) NOT NULL,
    audio_url TEXT,
    audio_duration_seconds INT,
    raw_transcript TEXT,
    segments_combined_transcript TEXT,
    refined_narrative TEXT,
    analysis_text TEXT,
    status VARCHAR(16) NOT NULL,
    narrative_hash VARCHAR(32),
    analysis_narrative_hash VARCHAR(32),
    analysis_revision INT NOT NULL DEFAULT 1,
    user_tags_locked INT NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id)
  )`,

  `CREATE INDEX IF NOT EXISTS idx_dreams_user_time ON dreams (user_id, occurred_at DESC)`,

  `CREATE TABLE IF NOT EXISTS dream_segments (
    id VARCHAR(64) PRIMARY KEY,
    dream_id VARCHAR(64) NOT NULL,
    segment_index INT NOT NULL,
    created_at VARCHAR(32) NOT NULL,
    audio_url TEXT,
    audio_duration_seconds INT,
    transcript TEXT,
    device_transcript TEXT,
    FOREIGN KEY (dream_id) REFERENCES dreams(id)
  )`,

  `CREATE INDEX IF NOT EXISTS idx_segments_dream_index ON dream_segments (dream_id, segment_index)`,

  `CREATE TABLE IF NOT EXISTS tags (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    category VARCHAR(32) NOT NULL,
    created_at VARCHAR(32) NOT NULL
  )`,

  `CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name_category ON tags (name, category)`,

  `CREATE TABLE IF NOT EXISTS dream_tags (
    id VARCHAR(64) PRIMARY KEY,
    dream_id VARCHAR(64) NOT NULL,
    tag_id VARCHAR(64) NOT NULL,
    relevance_score DOUBLE NOT NULL,
    FOREIGN KEY (dream_id) REFERENCES dreams(id),
    FOREIGN KEY (tag_id) REFERENCES tags(id)
  )`,

  `CREATE TABLE IF NOT EXISTS dream_visuals (
    id VARCHAR(64) PRIMARY KEY,
    dream_id VARCHAR(64) NOT NULL,
    user_id VARCHAR(64) NOT NULL,
    type VARCHAR(32) NOT NULL,
    style_key VARCHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL,
    created_at VARCHAR(32) NOT NULL,
    updated_at VARCHAR(32) NOT NULL,
    image_url TEXT,
    image_urls_json TEXT,
    seedream_call_count INT DEFAULT 0,
    successful_panel_count INT DEFAULT 0,
    estimated_cost_cny DOUBLE DEFAULT 0,
    failure_reason TEXT,
    failure_code VARCHAR(64),
    used_free_quota INT DEFAULT 0,
    narrative_hash_at_gen VARCHAR(32),
    FOREIGN KEY (dream_id) REFERENCES dreams(id)
  )`,

  `CREATE TABLE IF NOT EXISTS dream_comic_storyboards (
    dream_id VARCHAR(64) NOT NULL,
    style_key VARCHAR(64) NOT NULL,
    panels_json TEXT NOT NULL,
    narrative_hash VARCHAR(32) NOT NULL,
    updated_at VARCHAR(32) NOT NULL,
    PRIMARY KEY (dream_id, style_key),
    FOREIGN KEY (dream_id) REFERENCES dreams(id)
  )`,

  `CREATE TABLE IF NOT EXISTS dream_analysis_feedback (
    dream_id VARCHAR(64) PRIMARY KEY,
    feedback VARCHAR(32),
    optional_note TEXT,
    a_bit_off_sheet_seen INT NOT NULL DEFAULT 0,
    interpretation_revision INT DEFAULT 1,
    handled_at VARCHAR(32),
    updated_at VARCHAR(32) NOT NULL,
    FOREIGN KEY (dream_id) REFERENCES dreams(id)
  )`,

  `CREATE TABLE IF NOT EXISTS payment_orders (
    id VARCHAR(64) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    dream_id VARCHAR(64) NOT NULL,
    visual_id VARCHAR(64),
    product_id VARCHAR(128) NOT NULL,
    apple_transaction_id VARCHAR(128) NOT NULL UNIQUE,
    apple_original_transaction_id VARCHAR(128),
    environment VARCHAR(16) NOT NULL,
    status VARCHAR(32) NOT NULL,
    verified_at VARCHAR(32) NOT NULL,
    created_at VARCHAR(32) NOT NULL
  )`,

  `CREATE TABLE IF NOT EXISTS invite_codes (
    id VARCHAR(64) PRIMARY KEY,
    code VARCHAR(32) NOT NULL UNIQUE,
    batch_name VARCHAR(64) NOT NULL DEFAULT 'beta-100',
    channel_label VARCHAR(128),
    free_comic_quota INT NOT NULL DEFAULT 10,
    status VARCHAR(16) NOT NULL,
    redeemed_by_user_id VARCHAR(64),
    redeemed_at VARCHAR(32),
    created_at VARCHAR(32) NOT NULL
  )`,

  `CREATE TABLE IF NOT EXISTS user_comic_entitlements (
    user_id VARCHAR(64) PRIMARY KEY,
    invite_code_id VARCHAR(64),
    free_comics_total INT NOT NULL DEFAULT 0,
    free_comics_used INT NOT NULL DEFAULT 0,
    paid_comics_generated INT NOT NULL DEFAULT 0,
    updated_at VARCHAR(32) NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
  )`,

  `CREATE TABLE IF NOT EXISTS similarity_edges (
    id VARCHAR(64) PRIMARY KEY,
    dream_id_a VARCHAR(64) NOT NULL,
    dream_id_b VARCHAR(64) NOT NULL,
    score DOUBLE NOT NULL,
    shared_tag_ids TEXT NOT NULL,
    created_at VARCHAR(32) NOT NULL
  )`,

  `CREATE TABLE IF NOT EXISTS usage_daily (
    user_id VARCHAR(64) NOT NULL,
    day VARCHAR(10) NOT NULL,
    dream_analysis_count INT NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, day)
  )`,

  `CREATE TABLE IF NOT EXISTS device_push_tokens (
    id VARCHAR(64) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    token VARCHAR(512) NOT NULL,
    platform VARCHAR(16) NOT NULL DEFAULT 'ios',
    environment VARCHAR(16) NOT NULL,
    updated_at VARCHAR(32) NOT NULL,
    UNIQUE(user_id, token),
    FOREIGN KEY (user_id) REFERENCES users(id)
  )`,
];

/** Idempotent column/table adds for existing deployments */
export const SCHEMA_MIGRATION_STATEMENTS = [
  `ALTER TABLE dreams ADD COLUMN narrative_hash VARCHAR(32)`,
  `ALTER TABLE dreams ADD COLUMN analysis_narrative_hash VARCHAR(32)`,
  `ALTER TABLE dreams ADD COLUMN analysis_revision INT NOT NULL DEFAULT 1`,
  `ALTER TABLE dreams ADD COLUMN user_tags_locked INT NOT NULL DEFAULT 0`,
  `ALTER TABLE dream_visuals ADD COLUMN narrative_hash_at_gen VARCHAR(32)`,
  `ALTER TABLE dream_visuals ADD COLUMN failure_code VARCHAR(64)`,
  `ALTER TABLE dream_visuals ADD COLUMN push_sent_at VARCHAR(32)`,
];

export const MYSQL_INDEX_STATEMENTS = [
  `CREATE INDEX idx_dreams_user_time ON dreams (user_id, occurred_at DESC)`,
  `CREATE INDEX idx_segments_dream_index ON dream_segments (dream_id, segment_index)`,
  `CREATE UNIQUE INDEX idx_tags_name_category ON tags (name, category)`,
];

export function dailyAnalysisUpsertSql(backend: 'sqlite' | 'mysql'): string {
  if (backend === 'mysql') {
    return `INSERT INTO usage_daily (user_id, day, dream_analysis_count) VALUES (?, ?, 1)
      ON DUPLICATE KEY UPDATE dream_analysis_count = dream_analysis_count + 1`;
  }
  return `INSERT INTO usage_daily (user_id, day, dream_analysis_count) VALUES (?, ?, 1)
    ON CONFLICT(user_id, day) DO UPDATE SET dream_analysis_count = dream_analysis_count + 1`;
}
