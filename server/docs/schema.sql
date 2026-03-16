-- 用户表
CREATE TABLE users (
  id VARCHAR(64) PRIMARY KEY,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  auth_provider VARCHAR(16) NOT NULL,
  device_id VARCHAR(128),
  apple_id VARCHAR(128),
  wechat_id VARCHAR(128),
  age_range VARCHAR(16),
  gender_identity VARCHAR(32),
  color_preference VARCHAR(16)
);

-- 梦境主表
CREATE TABLE dreams (
  id VARCHAR(64) PRIMARY KEY,
  user_id VARCHAR(64) NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  occurred_at TIMESTAMP NOT NULL,
  source VARCHAR(16) NOT NULL,
  audio_url TEXT,
  audio_duration_seconds INT,
  raw_transcript TEXT,
  segments_combined_transcript TEXT,
  refined_narrative TEXT,
  analysis_text TEXT,
  status VARCHAR(16) NOT NULL,
  CONSTRAINT fk_dreams_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_dreams_user_time ON dreams (user_id, occurred_at DESC);

-- 分段录音
CREATE TABLE dream_segments (
  id VARCHAR(64) PRIMARY KEY,
  dream_id VARCHAR(64) NOT NULL,
  segment_index INT NOT NULL,
  created_at TIMESTAMP NOT NULL,
  audio_url TEXT,
  audio_duration_seconds INT,
  transcript TEXT,
  CONSTRAINT fk_segments_dream FOREIGN KEY (dream_id) REFERENCES dreams(id)
);

CREATE INDEX idx_segments_dream_index ON dream_segments (dream_id, segment_index);

-- 标签与关联
CREATE TABLE tags (
  id VARCHAR(64) PRIMARY KEY,
  name VARCHAR(128) NOT NULL,
  category VARCHAR(32) NOT NULL,
  created_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX idx_tags_name_category ON tags (name, category);

CREATE TABLE dream_tags (
  id VARCHAR(64) PRIMARY KEY,
  dream_id VARCHAR(64) NOT NULL,
  tag_id VARCHAR(64) NOT NULL,
  relevance_score NUMERIC(4, 3) NOT NULL,
  CONSTRAINT fk_dream_tags_dream FOREIGN KEY (dream_id) REFERENCES dreams(id),
  CONSTRAINT fk_dream_tags_tag FOREIGN KEY (tag_id) REFERENCES tags(id)
);

CREATE INDEX idx_dream_tags_dream ON dream_tags (dream_id);
CREATE INDEX idx_dream_tags_tag ON dream_tags (tag_id);

-- 显化作品
CREATE TABLE dream_visuals (
  id VARCHAR(64) PRIMARY KEY,
  dream_id VARCHAR(64) NOT NULL,
  type VARCHAR(32) NOT NULL,
  style_key VARCHAR(64) NOT NULL,
  status VARCHAR(32) NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  image_url TEXT,
  failure_reason TEXT,
  CONSTRAINT fk_visuals_dream FOREIGN KEY (dream_id) REFERENCES dreams(id)
);

CREATE INDEX idx_visuals_dream_type ON dream_visuals (dream_id, type);

-- 潜意识星图相似度边
CREATE TABLE similarity_edges (
  id VARCHAR(64) PRIMARY KEY,
  dream_id_a VARCHAR(64) NOT NULL,
  dream_id_b VARCHAR(64) NOT NULL,
  score NUMERIC(4, 3) NOT NULL,
  shared_tag_ids TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL,
  CONSTRAINT fk_edges_dream_a FOREIGN KEY (dream_id_a) REFERENCES dreams(id),
  CONSTRAINT fk_edges_dream_b FOREIGN KEY (dream_id_b) REFERENCES dreams(id)
);

CREATE INDEX idx_edges_dream_pair ON similarity_edges (dream_id_a, dream_id_b);

