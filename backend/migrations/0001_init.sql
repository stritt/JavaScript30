-- Stepquest initial schema

CREATE TABLE players (
  id            TEXT PRIMARY KEY,
  apple_sub     TEXT UNIQUE,
  dev_device_id TEXT UNIQUE,
  display_name  TEXT NOT NULL,
  hero_level    INTEGER NOT NULL DEFAULT 1,
  zone          INTEGER NOT NULL DEFAULT 1,
  region        TEXT,
  local_opt_in  INTEGER NOT NULL DEFAULT 0,
  flagged       INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL
);

CREATE INDEX idx_players_region ON players(region) WHERE local_opt_in = 1;

-- One row per player per local calendar day. Re-uploads keep the max.
CREATE TABLE step_days (
  player_id  TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  day        TEXT NOT NULL,           -- YYYY-MM-DD (player's local date)
  week       TEXT NOT NULL,           -- ISO week of `day`, e.g. 2026-W40
  steps      INTEGER NOT NULL,
  flights    INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (player_id, day)
);

CREATE INDEX idx_step_days_week ON step_days(player_id, week);

-- Friendships are stored in both directions.
CREATE TABLE friendships (
  player_id  TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  friend_id  TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (player_id, friend_id)
);

CREATE TABLE invites (
  code       TEXT PRIMARY KEY,
  player_id  TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL
);

-- Archived weekly standings written by the Monday cron.
CREATE TABLE season_results (
  week      TEXT NOT NULL,
  board     TEXT NOT NULL,            -- e.g. global|steps, local:US-CA-San Francisco|steps
  player_id TEXT NOT NULL,
  rank      INTEGER NOT NULL,
  value     INTEGER NOT NULL,
  PRIMARY KEY (week, board, player_id)
);
