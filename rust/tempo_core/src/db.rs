use chrono::{Local, NaiveDate, Utc};
use rusqlite::{params, Connection, OptionalExtension, Result as SqlResult};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use uuid::Uuid;

use crate::models::*;

pub fn now_iso() -> String {
    Utc::now().to_rfc3339()
}

pub fn today_key() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

pub fn compute_bmi(height_cm: f64, weight_kg: f64) -> f64 {
    if height_cm < 50.0 || height_cm > 300.0 || weight_kg < 15.0 || weight_kg > 450.0 {
        return 0.0;
    }
    let h_m = height_cm / 100.0;
    let bmi = weight_kg / (h_m * h_m);
    if bmi.is_finite() {
        (bmi * 10.0).round() / 10.0
    } else {
        0.0
    }
}

pub fn hash_pin(profile_id: &str, pin: &str) -> String {
    let trimmed = pin.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut hasher = Sha256::new();
    hasher.update(b"tempo_local_pin_v1:");
    hasher.update(profile_id.as_bytes());
    hasher.update(b":");
    hasher.update(trimmed.as_bytes());
    hex::encode(hasher.finalize())
}

pub fn init_schema(conn: &Connection) -> SqlResult<()> {
    conn.execute_batch(
        "
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;
        PRAGMA synchronous = NORMAL;

        CREATE TABLE IF NOT EXISTS profiles (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            avatar_path TEXT NOT NULL DEFAULT '',
            pin_hash TEXT NOT NULL DEFAULT '',
            gender TEXT NOT NULL DEFAULT '',
            birthdate TEXT NOT NULL DEFAULT '',
            age INTEGER NOT NULL DEFAULT 0,
            height_cm REAL NOT NULL DEFAULT 0,
            weight_kg REAL NOT NULL DEFAULT 0,
            waist_cm REAL NOT NULL DEFAULT 0,
            sleep_hours REAL NOT NULL DEFAULT 0,
            bmi REAL NOT NULL DEFAULT 0,
            fitness_goal TEXT NOT NULL DEFAULT 'general_fitness',
            selected_journey_id TEXT NOT NULL DEFAULT '',
            selected_journey_name TEXT NOT NULL DEFAULT '',
            daily_calories_goal INTEGER NOT NULL DEFAULT 2500,
            daily_minutes_goal INTEGER NOT NULL DEFAULT 60,
            daily_workouts_goal INTEGER NOT NULL DEFAULT 3,
            daily_steps_goal INTEGER NOT NULL DEFAULT 10000,
            has_completed_profile INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS daily_activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            date_key TEXT NOT NULL,
            steps INTEGER NOT NULL DEFAULT 0,
            calories INTEGER NOT NULL DEFAULT 0,
            minutes INTEGER NOT NULL DEFAULT 0,
            workouts_count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            UNIQUE(profile_id, date_key)
        );
        CREATE INDEX IF NOT EXISTS idx_daily_activity_profile_date
            ON daily_activity(profile_id, date_key DESC);

        CREATE TABLE IF NOT EXISTS body_metrics_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            metric_type TEXT NOT NULL,
            value REAL NOT NULL,
            recorded_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_body_metrics_profile_type
            ON body_metrics_history(profile_id, metric_type, recorded_at DESC);

        CREATE TABLE IF NOT EXISTS completed_workouts (
            id TEXT PRIMARY KEY,
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            workout_id TEXT NOT NULL,
            title TEXT NOT NULL,
            duration_label TEXT NOT NULL DEFAULT '',
            exercises_label TEXT NOT NULL DEFAULT '',
            level TEXT NOT NULL DEFAULT '',
            body_focus TEXT NOT NULL DEFAULT '',
            journey_id TEXT NOT NULL DEFAULT '',
            journey_name TEXT NOT NULL DEFAULT '',
            actual_duration_sec INTEGER NOT NULL DEFAULT 0,
            expected_duration_sec INTEGER NOT NULL DEFAULT 0,
            calories_burned INTEGER NOT NULL DEFAULT 0,
            is_cheated INTEGER NOT NULL DEFAULT 0,
            completed_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_completed_workouts_profile_date
            ON completed_workouts(profile_id, completed_at DESC);

        CREATE TABLE IF NOT EXISTS exercise_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            exercise_name TEXT NOT NULL,
            workout_id TEXT NOT NULL DEFAULT '',
            weight_used REAL NOT NULL DEFAULT 0,
            reps_performed INTEGER NOT NULL DEFAULT 0,
            sets_performed INTEGER NOT NULL DEFAULT 0,
            body_focus TEXT NOT NULL DEFAULT '',
            level TEXT NOT NULL DEFAULT '',
            journey_id TEXT NOT NULL DEFAULT '',
            journey_name TEXT NOT NULL DEFAULT '',
            primary_goal TEXT NOT NULL DEFAULT '',
            goal_tags_json TEXT NOT NULL DEFAULT '[]',
            recorded_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_exercise_records_profile_name
            ON exercise_records(profile_id, exercise_name, recorded_at DESC);

        CREATE TABLE IF NOT EXISTS journey_progress (
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            journey_id TEXT NOT NULL,
            journey_name TEXT NOT NULL,
            is_selected INTEGER NOT NULL DEFAULT 0,
            is_completed INTEGER NOT NULL DEFAULT 0,
            completed_workouts_count INTEGER NOT NULL DEFAULT 0,
            cheated_workouts_count INTEGER NOT NULL DEFAULT 0,
            clean_workouts_count INTEGER NOT NULL DEFAULT 0,
            total_workouts_count INTEGER NOT NULL DEFAULT 0,
            completion_count INTEGER NOT NULL DEFAULT 0,
            progress_percent REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'not_started',
            started_at TEXT,
            active_cycle_started_at TEXT,
            completed_at TEXT,
            next_workout_id TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (profile_id, journey_id)
        );

        CREATE TABLE IF NOT EXISTS progress_photos (
            id TEXT PRIMARY KEY,
            profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            file_path TEXT NOT NULL,
            caption TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'General',
            weight_kg REAL,
            taken_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_progress_photos_profile_date
            ON progress_photos(profile_id, taken_at DESC);

        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        ",
    )?;
    Ok(())
}

fn row_to_profile(row: &rusqlite::Row<'_>) -> SqlResult<Profile> {
    let pin_hash: String = row.get(3)?;
    Ok(Profile {
        id: row.get(0)?,
        display_name: row.get(1)?,
        avatar_path: row.get(2)?,
        has_pin: !pin_hash.is_empty(),
        gender: row.get(4)?,
        birthdate: row.get(5)?,
        age: row.get(6)?,
        height_cm: row.get(7)?,
        weight_kg: row.get(8)?,
        waist_cm: row.get(9)?,
        sleep_hours: row.get(10)?,
        bmi: row.get(11)?,
        fitness_goal: row.get(12)?,
        selected_journey_id: row.get(13)?,
        selected_journey_name: row.get(14)?,
        daily_calories_goal: row.get(15)?,
        daily_minutes_goal: row.get(16)?,
        daily_workouts_goal: row.get(17)?,
        daily_steps_goal: row.get(18)?,
        has_completed_profile: row.get::<_, i32>(19)? != 0,
        created_at: row.get(20)?,
        updated_at: row.get(21)?,
    })
}

const PROFILE_SELECT_COLS: &str = "id, display_name, avatar_path, pin_hash, gender, birthdate, age, height_cm, weight_kg, waist_cm, sleep_hours, bmi, fitness_goal, selected_journey_id, selected_journey_name, daily_calories_goal, daily_minutes_goal, daily_workouts_goal, daily_steps_goal, has_completed_profile, created_at, updated_at";

pub fn list_profiles(conn: &Connection) -> SqlResult<Vec<Profile>> {
    let sql = format!(
        "SELECT {} FROM profiles ORDER BY created_at ASC",
        PROFILE_SELECT_COLS
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map([], row_to_profile)?;
    let mut result = Vec::new();
    for r in rows {
        result.push(r?);
    }
    Ok(result)
}

pub fn get_profile(conn: &Connection, id: &str) -> SqlResult<Option<Profile>> {
    let sql = format!("SELECT {} FROM profiles WHERE id = ?1", PROFILE_SELECT_COLS);
    conn.query_row(&sql, params![id], row_to_profile).optional()
}

pub fn create_profile(conn: &Connection, input: CreateProfileInput) -> Result<Profile, String> {
    let name = input.display_name.trim();
    if name.is_empty() {
        return Err("Display name cannot be empty".to_string());
    }
    let pin = input.pin.trim();
    if pin.len() != 4 || !pin.chars().all(|c| c.is_ascii_digit()) {
        return Err("PIN must be exactly 4 digits".to_string());
    }

    let id = Uuid::new_v4().to_string();
    let pin_hash = hash_pin(&id, pin);
    let bmi = compute_bmi(input.height_cm, input.weight_kg);
    let now = now_iso();

    conn.execute(
        "INSERT INTO profiles (
            id, display_name, avatar_path, pin_hash, gender, birthdate, age,
            height_cm, weight_kg, waist_cm, sleep_hours, bmi, fitness_goal,
            daily_calories_goal, daily_minutes_goal, daily_workouts_goal, daily_steps_goal,
            has_completed_profile, created_at, updated_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20)",
        params![
            id,
            name,
            input.avatar_path,
            pin_hash,
            input.gender,
            input.birthdate,
            input.age,
            input.height_cm,
            input.weight_kg,
            input.waist_cm,
            input.sleep_hours,
            bmi,
            input.fitness_goal,
            input.daily_calories_goal,
            input.daily_minutes_goal,
            input.daily_workouts_goal,
            input.daily_steps_goal,
            if input.has_completed_profile { 1 } else { 0 },
            now,
            now
        ],
    )
    .map_err(|e| e.to_string())?;

    // Seed initial body metric points if provided
    if input.weight_kg > 0.0 {
        let _ = conn.execute(
            "INSERT INTO body_metrics_history (profile_id, metric_type, value, recorded_at) VALUES (?1, 'weight', ?2, ?3)",
            params![id, input.weight_kg, now],
        );
    }
    if input.waist_cm > 0.0 {
        let _ = conn.execute(
            "INSERT INTO body_metrics_history (profile_id, metric_type, value, recorded_at) VALUES (?1, 'waist', ?2, ?3)",
            params![id, input.waist_cm, now],
        );
    }
    if input.sleep_hours > 0.0 {
        let _ = conn.execute(
            "INSERT INTO body_metrics_history (profile_id, metric_type, value, recorded_at) VALUES (?1, 'sleep', ?2, ?3)",
            params![id, input.sleep_hours, now],
        );
    }

    get_profile(conn, &id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Created profile not found".to_string())
}

pub fn verify_pin(conn: &Connection, profile_id: &str, pin: &str) -> Result<bool, String> {
    let stored: Option<String> = conn
        .query_row(
            "SELECT pin_hash FROM profiles WHERE id = ?1",
            params![profile_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    match stored {
        None => Err("Profile not found".to_string()),
        Some(hash) => {
            if hash.is_empty() {
                Ok(true)
            } else {
                Ok(hash == hash_pin(profile_id, pin))
            }
        }
    }
}

pub fn update_profile_pin(
    conn: &Connection,
    profile_id: &str,
    current_pin: &str,
    new_pin: &str,
) -> Result<bool, String> {
    if !verify_pin(conn, profile_id, current_pin)? {
        return Err("Current PIN is incorrect".to_string());
    }
    let clean = new_pin.trim();
    if clean.len() != 4 || !clean.chars().all(|c| c.is_ascii_digit()) {
        return Err("New PIN must be exactly 4 digits".to_string());
    }
    let new_hash = hash_pin(profile_id, clean);
    conn.execute(
        "UPDATE profiles SET pin_hash = ?1, updated_at = ?2 WHERE id = ?3",
        params![new_hash, now_iso(), profile_id],
    )
    .map_err(|e| e.to_string())?;
    Ok(true)
}

pub fn update_profile(conn: &Connection, input: UpdateProfileInput) -> Result<Profile, String> {
    let existing = get_profile(conn, &input.id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Profile not found".to_string())?;

    let display_name = input
        .display_name
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or(existing.display_name);
    let avatar_path = input.avatar_path.unwrap_or(existing.avatar_path);
    let gender = input.gender.unwrap_or(existing.gender);
    let birthdate = input.birthdate.unwrap_or(existing.birthdate);
    let age = input.age.unwrap_or(existing.age);
    let height_cm = input.height_cm.unwrap_or(existing.height_cm);
    let weight_kg = input.weight_kg.unwrap_or(existing.weight_kg);
    let waist_cm = input.waist_cm.unwrap_or(existing.waist_cm);
    let sleep_hours = input.sleep_hours.unwrap_or(existing.sleep_hours);
    let bmi = compute_bmi(height_cm, weight_kg);
    let fitness_goal = input.fitness_goal.unwrap_or(existing.fitness_goal);
    let selected_journey_id = input
        .selected_journey_id
        .unwrap_or(existing.selected_journey_id);
    let selected_journey_name = input
        .selected_journey_name
        .unwrap_or(existing.selected_journey_name);
    let daily_calories_goal = input
        .daily_calories_goal
        .unwrap_or(existing.daily_calories_goal);
    let daily_minutes_goal = input
        .daily_minutes_goal
        .unwrap_or(existing.daily_minutes_goal);
    let daily_workouts_goal = input
        .daily_workouts_goal
        .unwrap_or(existing.daily_workouts_goal);
    let daily_steps_goal = input.daily_steps_goal.unwrap_or(existing.daily_steps_goal);
    let has_completed_profile = input
        .has_completed_profile
        .unwrap_or(existing.has_completed_profile);
    let now = now_iso();

    conn.execute(
        "UPDATE profiles SET
            display_name = ?1, avatar_path = ?2, gender = ?3, birthdate = ?4, age = ?5,
            height_cm = ?6, weight_kg = ?7, waist_cm = ?8, sleep_hours = ?9, bmi = ?10,
            fitness_goal = ?11, selected_journey_id = ?12, selected_journey_name = ?13,
            daily_calories_goal = ?14, daily_minutes_goal = ?15, daily_workouts_goal = ?16,
            daily_steps_goal = ?17, has_completed_profile = ?18, updated_at = ?19
         WHERE id = ?20",
        params![
            display_name,
            avatar_path,
            gender,
            birthdate,
            age,
            height_cm,
            weight_kg,
            waist_cm,
            sleep_hours,
            bmi,
            fitness_goal,
            selected_journey_id,
            selected_journey_name,
            daily_calories_goal,
            daily_minutes_goal,
            daily_workouts_goal,
            daily_steps_goal,
            if has_completed_profile { 1 } else { 0 },
            now,
            input.id
        ],
    )
    .map_err(|e| e.to_string())?;

    get_profile(conn, &input.id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Updated profile not found".to_string())
}

pub fn delete_profile(conn: &Connection, profile_id: &str) -> Result<bool, String> {
    let changed = conn
        .execute("DELETE FROM profiles WHERE id = ?1", params![profile_id])
        .map_err(|e| e.to_string())?;
    Ok(changed > 0)
}

pub fn get_setting(conn: &Connection, key: &str) -> SqlResult<Option<String>> {
    conn.query_row(
        "SELECT value FROM app_settings WHERE key = ?1",
        params![key],
        |row| row.get(0),
    )
    .optional()
}

pub fn set_setting(conn: &Connection, key: &str, value: &str) -> SqlResult<()> {
    conn.execute(
        "INSERT INTO app_settings (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

pub fn upsert_daily_activity(
    conn: &Connection,
    input: UpsertDailyActivityInput,
) -> Result<DailyActivityEntry, String> {
    let existing: Option<(i32, i32, i32, i32)> = conn
        .query_row(
            "SELECT steps, calories, minutes, workouts_count FROM daily_activity
             WHERE profile_id = ?1 AND date_key = ?2",
            params![input.profile_id, input.date_key],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let (cur_steps, cur_cals, cur_mins, cur_workouts) = existing.unwrap_or((0, 0, 0, 0));
    let (steps, calories, minutes, workouts_count) = if input.increment {
        (
            cur_steps + input.steps.unwrap_or(0),
            cur_cals + input.calories.unwrap_or(0),
            cur_mins + input.minutes.unwrap_or(0),
            cur_workouts + input.workouts_count.unwrap_or(0),
        )
    } else {
        (
            input.steps.unwrap_or(cur_steps),
            input.calories.unwrap_or(cur_cals),
            input.minutes.unwrap_or(cur_mins),
            input.workouts_count.unwrap_or(cur_workouts),
        )
    };

    let now = now_iso();
    conn.execute(
        "INSERT INTO daily_activity (profile_id, date_key, steps, calories, minutes, workouts_count, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(profile_id, date_key) DO UPDATE SET
            steps = excluded.steps,
            calories = excluded.calories,
            minutes = excluded.minutes,
            workouts_count = excluded.workouts_count,
            updated_at = excluded.updated_at",
        params![
            input.profile_id,
            input.date_key,
            steps.max(0),
            calories.max(0),
            minutes.max(0),
            workouts_count.max(0),
            now
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(DailyActivityEntry {
        date_key: input.date_key,
        steps: steps.max(0),
        calories: calories.max(0),
        minutes: minutes.max(0),
        workouts_count: workouts_count.max(0),
        updated_at: now,
    })
}

pub fn get_daily_activity_history(
    conn: &Connection,
    profile_id: &str,
    limit: i32,
) -> SqlResult<Vec<DailyActivityEntry>> {
    let mut stmt = conn.prepare(
        "SELECT date_key, steps, calories, minutes, workouts_count, updated_at
         FROM daily_activity
         WHERE profile_id = ?1
         ORDER BY date_key DESC
         LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![profile_id, limit], |row| {
        Ok(DailyActivityEntry {
            date_key: row.get(0)?,
            steps: row.get(1)?,
            calories: row.get(2)?,
            minutes: row.get(3)?,
            workouts_count: row.get(4)?,
            updated_at: row.get(5)?,
        })
    })?;
    let mut items: Vec<DailyActivityEntry> = rows.collect::<SqlResult<_>>()?;
    items.reverse(); // chronological ascending
    Ok(items)
}

pub fn log_body_metric(
    conn: &mut Connection,
    input: LogBodyMetricInput,
) -> Result<Profile, String> {
    let metric = input.metric_type.trim().to_lowercase();
    if !["weight", "waist", "sleep", "height"].contains(&metric.as_str()) {
        return Err(format!("Unsupported metric type: {}", metric));
    }
    let recorded_at = input.recorded_at.unwrap_or_else(now_iso);
    let now = now_iso();

    let tx = conn.transaction().map_err(|e| e.to_string())?;

    if metric != "height" {
        tx.execute(
            "INSERT INTO body_metrics_history (profile_id, metric_type, value, recorded_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![input.profile_id, metric, input.value, recorded_at],
        )
        .map_err(|e| e.to_string())?;
    }

    let (height_cm, weight_kg): (f64, f64) = tx
        .query_row(
            "SELECT height_cm, weight_kg FROM profiles WHERE id = ?1",
            params![input.profile_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|e| e.to_string())?;

    let new_height = if metric == "height" {
        input.value
    } else {
        height_cm
    };
    let new_weight = if metric == "weight" {
        input.value
    } else {
        weight_kg
    };
    let new_bmi = compute_bmi(new_height, new_weight);

    match metric.as_str() {
        "weight" => {
            tx.execute(
                "UPDATE profiles SET weight_kg = ?1, bmi = ?2, updated_at = ?3 WHERE id = ?4",
                params![input.value, new_bmi, now, input.profile_id],
            )
            .map_err(|e| e.to_string())?;
        }
        "height" => {
            tx.execute(
                "UPDATE profiles SET height_cm = ?1, bmi = ?2, updated_at = ?3 WHERE id = ?4",
                params![input.value, new_bmi, now, input.profile_id],
            )
            .map_err(|e| e.to_string())?;
        }
        "waist" => {
            tx.execute(
                "UPDATE profiles SET waist_cm = ?1, updated_at = ?2 WHERE id = ?3",
                params![input.value, now, input.profile_id],
            )
            .map_err(|e| e.to_string())?;
        }
        "sleep" => {
            tx.execute(
                "UPDATE profiles SET sleep_hours = ?1, updated_at = ?2 WHERE id = ?3",
                params![input.value, now, input.profile_id],
            )
            .map_err(|e| e.to_string())?;
        }
        _ => {}
    }

    tx.commit().map_err(|e| e.to_string())?;

    get_profile(conn, &input.profile_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Profile not found".to_string())
}

pub fn get_body_metric_history(
    conn: &Connection,
    profile_id: &str,
    metric_type: &str,
    limit: i32,
) -> SqlResult<Vec<BodyMetricPoint>> {
    let mut stmt = conn.prepare(
        "SELECT id, metric_type, value, recorded_at
         FROM body_metrics_history
         WHERE profile_id = ?1 AND metric_type = ?2
         ORDER BY recorded_at DESC
         LIMIT ?3",
    )?;
    let rows = stmt.query_map(params![profile_id, metric_type, limit], |row| {
        Ok(BodyMetricPoint {
            id: row.get(0)?,
            metric_type: row.get(1)?,
            value: row.get(2)?,
            recorded_at: row.get(3)?,
        })
    })?;
    let mut pts: Vec<BodyMetricPoint> = rows.collect::<SqlResult<_>>()?;
    pts.reverse();
    Ok(pts)
}

pub fn log_completed_workout(
    conn: &mut Connection,
    input: LogCompletedWorkoutInput,
) -> Result<CompletedWorkout, String> {
    let id = Uuid::new_v4().to_string();
    let completed_at = input.completed_at.unwrap_or_else(now_iso);
    let date_key = input.date_key.unwrap_or_else(today_key);
    let minutes = (input.actual_duration_sec / 60).max(1);

    let tx = conn.transaction().map_err(|e| e.to_string())?;
    tx.execute(
        "INSERT INTO completed_workouts (
            id, profile_id, workout_id, title, duration_label, exercises_label,
            level, body_focus, journey_id, journey_name,
            actual_duration_sec, expected_duration_sec, calories_burned,
            is_cheated, completed_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)",
        params![
            id,
            input.profile_id,
            input.workout_id,
            input.title,
            input.duration_label,
            input.exercises_label,
            input.level,
            input.body_focus,
            input.journey_id,
            input.journey_name,
            input.actual_duration_sec,
            input.expected_duration_sec,
            input.calories_burned,
            if input.is_cheated { 1 } else { 0 },
            completed_at
        ],
    )
    .map_err(|e| e.to_string())?;

    if !input.is_cheated {
        let now = now_iso();
        tx.execute(
            "INSERT INTO daily_activity (profile_id, date_key, steps, calories, minutes, workouts_count, updated_at)
             VALUES (?1, ?2, 0, ?3, ?4, 1, ?5)
             ON CONFLICT(profile_id, date_key) DO UPDATE SET
                calories = daily_activity.calories + excluded.calories,
                minutes = daily_activity.minutes + excluded.minutes,
                workouts_count = daily_activity.workouts_count + 1,
                updated_at = excluded.updated_at",
            params![input.profile_id, date_key, input.calories_burned, minutes, now],
        )
        .map_err(|e| e.to_string())?;
    }

    tx.commit().map_err(|e| e.to_string())?;

    Ok(CompletedWorkout {
        id,
        profile_id: input.profile_id,
        workout_id: input.workout_id,
        title: input.title,
        duration_label: input.duration_label,
        exercises_label: input.exercises_label,
        level: input.level,
        body_focus: input.body_focus,
        journey_id: input.journey_id,
        journey_name: input.journey_name,
        actual_duration_sec: input.actual_duration_sec,
        expected_duration_sec: input.expected_duration_sec,
        calories_burned: input.calories_burned,
        is_cheated: input.is_cheated,
        completed_at,
    })
}

pub fn get_completed_workouts(
    conn: &Connection,
    profile_id: &str,
    limit: i32,
) -> SqlResult<Vec<CompletedWorkout>> {
    let mut stmt = conn.prepare(
        "SELECT id, profile_id, workout_id, title, duration_label, exercises_label,
                level, body_focus, journey_id, journey_name,
                actual_duration_sec, expected_duration_sec, calories_burned,
                is_cheated, completed_at
         FROM completed_workouts
         WHERE profile_id = ?1
         ORDER BY completed_at DESC
         LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![profile_id, limit], |row| {
        Ok(CompletedWorkout {
            id: row.get(0)?,
            profile_id: row.get(1)?,
            workout_id: row.get(2)?,
            title: row.get(3)?,
            duration_label: row.get(4)?,
            exercises_label: row.get(5)?,
            level: row.get(6)?,
            body_focus: row.get(7)?,
            journey_id: row.get(8)?,
            journey_name: row.get(9)?,
            actual_duration_sec: row.get(10)?,
            expected_duration_sec: row.get(11)?,
            calories_burned: row.get(12)?,
            is_cheated: row.get::<_, i32>(13)? != 0,
            completed_at: row.get(14)?,
        })
    })?;
    rows.collect()
}

pub fn log_exercise_record(
    conn: &Connection,
    input: LogExerciseRecordInput,
) -> Result<ExerciseRecordItem, String> {
    let recorded_at = input.recorded_at.unwrap_or_else(now_iso);
    let goal_tags_json = serde_json::to_string(&input.goal_tags).unwrap_or_else(|_| "[]".to_string());

    conn.execute(
        "INSERT INTO exercise_records (
            profile_id, exercise_name, workout_id, weight_used, reps_performed, sets_performed,
            body_focus, level, journey_id, journey_name, primary_goal, goal_tags_json, recorded_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
        params![
            input.profile_id,
            input.exercise_name,
            input.workout_id,
            input.weight_used,
            input.reps_performed,
            input.sets_performed,
            input.body_focus,
            input.level,
            input.journey_id,
            input.journey_name,
            input.primary_goal,
            goal_tags_json,
            recorded_at
        ],
    )
    .map_err(|e| e.to_string())?;

    let id = conn.last_insert_rowid();
    Ok(ExerciseRecordItem {
        id,
        profile_id: input.profile_id,
        exercise_name: input.exercise_name,
        workout_id: input.workout_id,
        weight_used: input.weight_used,
        reps_performed: input.reps_performed,
        sets_performed: input.sets_performed,
        body_focus: input.body_focus,
        level: input.level,
        journey_id: input.journey_id,
        journey_name: input.journey_name,
        primary_goal: input.primary_goal,
        goal_tags: input.goal_tags,
        recorded_at,
    })
}

pub fn get_exercise_records(
    conn: &Connection,
    profile_id: &str,
    exercise_name: Option<&str>,
) -> SqlResult<Vec<ExerciseRecordItem>> {
    let mut results = Vec::new();
    if let Some(name) = exercise_name {
        let mut stmt = conn.prepare(
            "SELECT id, profile_id, exercise_name, workout_id, weight_used, reps_performed, sets_performed,
                    body_focus, level, journey_id, journey_name, primary_goal, goal_tags_json, recorded_at
             FROM exercise_records
             WHERE profile_id = ?1 AND exercise_name = ?2
             ORDER BY recorded_at DESC",
        )?;
        let rows = stmt.query_map(params![profile_id, name], row_to_exercise_record)?;
        for r in rows {
            results.push(r?);
        }
    } else {
        let mut stmt = conn.prepare(
            "SELECT id, profile_id, exercise_name, workout_id, weight_used, reps_performed, sets_performed,
                    body_focus, level, journey_id, journey_name, primary_goal, goal_tags_json, recorded_at
             FROM exercise_records
             WHERE profile_id = ?1
             ORDER BY recorded_at DESC",
        )?;
        let rows = stmt.query_map(params![profile_id], row_to_exercise_record)?;
        for r in rows {
            results.push(r?);
        }
    }
    Ok(results)
}

fn row_to_exercise_record(row: &rusqlite::Row<'_>) -> SqlResult<ExerciseRecordItem> {
    let tags_raw: String = row.get(12)?;
    let goal_tags: Vec<String> = serde_json::from_str(&tags_raw).unwrap_or_default();
    Ok(ExerciseRecordItem {
        id: row.get(0)?,
        profile_id: row.get(1)?,
        exercise_name: row.get(2)?,
        workout_id: row.get(3)?,
        weight_used: row.get(4)?,
        reps_performed: row.get(5)?,
        sets_performed: row.get(6)?,
        body_focus: row.get(7)?,
        level: row.get(8)?,
        journey_id: row.get(9)?,
        journey_name: row.get(10)?,
        primary_goal: row.get(11)?,
        goal_tags,
        recorded_at: row.get(13)?,
    })
}

pub fn upsert_journey_progress(
    conn: &mut Connection,
    record: JourneyProgressRecord,
) -> Result<JourneyProgressRecord, String> {
    let now = now_iso();
    let tx = conn.transaction().map_err(|e| e.to_string())?;

    if record.is_selected {
        tx.execute(
            "UPDATE journey_progress SET is_selected = 0, updated_at = ?1 WHERE profile_id = ?2",
            params![now, record.profile_id],
        )
        .map_err(|e| e.to_string())?;
        tx.execute(
            "UPDATE profiles SET selected_journey_id = ?1, selected_journey_name = ?2, updated_at = ?3 WHERE id = ?4",
            params![record.journey_id, record.journey_name, now, record.profile_id],
        )
        .map_err(|e| e.to_string())?;
    }

    tx.execute(
        "INSERT INTO journey_progress (
            profile_id, journey_id, journey_name, is_selected, is_completed,
            completed_workouts_count, cheated_workouts_count, clean_workouts_count,
            total_workouts_count, completion_count, progress_percent, status,
            started_at, active_cycle_started_at, completed_at, next_workout_id, updated_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
        ON CONFLICT(profile_id, journey_id) DO UPDATE SET
            journey_name = excluded.journey_name,
            is_selected = excluded.is_selected,
            is_completed = excluded.is_completed,
            completed_workouts_count = excluded.completed_workouts_count,
            cheated_workouts_count = excluded.cheated_workouts_count,
            clean_workouts_count = excluded.clean_workouts_count,
            total_workouts_count = excluded.total_workouts_count,
            completion_count = excluded.completion_count,
            progress_percent = excluded.progress_percent,
            status = excluded.status,
            started_at = excluded.started_at,
            active_cycle_started_at = excluded.active_cycle_started_at,
            completed_at = excluded.completed_at,
            next_workout_id = excluded.next_workout_id,
            updated_at = excluded.updated_at",
        params![
            record.profile_id,
            record.journey_id,
            record.journey_name,
            if record.is_selected { 1 } else { 0 },
            if record.is_completed { 1 } else { 0 },
            record.completed_workouts_count,
            record.cheated_workouts_count,
            record.clean_workouts_count,
            record.total_workouts_count,
            record.completion_count,
            record.progress_percent,
            record.status,
            record.started_at,
            record.active_cycle_started_at,
            record.completed_at,
            record.next_workout_id,
            now
        ],
    )
    .map_err(|e| e.to_string())?;

    tx.commit().map_err(|e| e.to_string())?;

    Ok(JourneyProgressRecord {
        updated_at: now,
        ..record
    })
}

pub fn get_journey_progress(
    conn: &Connection,
    profile_id: &str,
    journey_id: Option<&str>,
) -> SqlResult<Vec<JourneyProgressRecord>> {
    let mut results = Vec::new();
    if let Some(jid) = journey_id {
        let mut stmt = conn.prepare(
            "SELECT profile_id, journey_id, journey_name, is_selected, is_completed,
                    completed_workouts_count, cheated_workouts_count, clean_workouts_count,
                    total_workouts_count, completion_count, progress_percent, status,
                    started_at, active_cycle_started_at, completed_at, next_workout_id, updated_at
             FROM journey_progress
             WHERE profile_id = ?1 AND journey_id = ?2",
        )?;
        let rows = stmt.query_map(params![profile_id, jid], row_to_journey_progress)?;
        for r in rows {
            results.push(r?);
        }
    } else {
        let mut stmt = conn.prepare(
            "SELECT profile_id, journey_id, journey_name, is_selected, is_completed,
                    completed_workouts_count, cheated_workouts_count, clean_workouts_count,
                    total_workouts_count, completion_count, progress_percent, status,
                    started_at, active_cycle_started_at, completed_at, next_workout_id, updated_at
             FROM journey_progress
             WHERE profile_id = ?1",
        )?;
        let rows = stmt.query_map(params![profile_id], row_to_journey_progress)?;
        for r in rows {
            results.push(r?);
        }
    }
    Ok(results)
}

fn row_to_journey_progress(row: &rusqlite::Row<'_>) -> SqlResult<JourneyProgressRecord> {
    Ok(JourneyProgressRecord {
        profile_id: row.get(0)?,
        journey_id: row.get(1)?,
        journey_name: row.get(2)?,
        is_selected: row.get::<_, i32>(3)? != 0,
        is_completed: row.get::<_, i32>(4)? != 0,
        completed_workouts_count: row.get(5)?,
        cheated_workouts_count: row.get(6)?,
        clean_workouts_count: row.get(7)?,
        total_workouts_count: row.get(8)?,
        completion_count: row.get(9)?,
        progress_percent: row.get(10)?,
        status: row.get(11)?,
        started_at: row.get(12)?,
        active_cycle_started_at: row.get(13)?,
        completed_at: row.get(14)?,
        next_workout_id: row.get(15)?,
        updated_at: row.get(16)?,
    })
}

pub fn add_progress_photo(
    conn: &Connection,
    input: AddProgressPhotoInput,
) -> Result<ProgressPhoto, String> {
    let id = Uuid::new_v4().to_string();
    let taken_at = input.taken_at.unwrap_or_else(now_iso);
    conn.execute(
        "INSERT INTO progress_photos (id, profile_id, file_path, caption, category, weight_kg, taken_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            id,
            input.profile_id,
            input.file_path,
            input.caption,
            input.category,
            input.weight_kg,
            taken_at
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(ProgressPhoto {
        id,
        profile_id: input.profile_id,
        file_path: input.file_path,
        caption: input.caption,
        category: input.category,
        weight_kg: input.weight_kg,
        taken_at,
    })
}

pub fn list_progress_photos(conn: &Connection, profile_id: &str) -> SqlResult<Vec<ProgressPhoto>> {
    let mut stmt = conn.prepare(
        "SELECT id, profile_id, file_path, caption, category, weight_kg, taken_at
         FROM progress_photos
         WHERE profile_id = ?1
         ORDER BY taken_at DESC",
    )?;
    let rows = stmt.query_map(params![profile_id], |row| {
        Ok(ProgressPhoto {
            id: row.get(0)?,
            profile_id: row.get(1)?,
            file_path: row.get(2)?,
            caption: row.get(3)?,
            category: row.get(4)?,
            weight_kg: row.get(5)?,
            taken_at: row.get(6)?,
        })
    })?;
    rows.collect()
}

pub fn delete_progress_photo(conn: &Connection, photo_id: &str) -> Result<bool, String> {
    let n = conn
        .execute("DELETE FROM progress_photos WHERE id = ?1", params![photo_id])
        .map_err(|e| e.to_string())?;
    Ok(n > 0)
}

pub fn compute_streaks(conn: &Connection, profile_id: &str, today: &str) -> (i32, i32) {
    let mut stmt = match conn.prepare(
        "SELECT completed_at FROM completed_workouts WHERE profile_id = ?1 AND is_cheated = 0",
    ) {
        Ok(s) => s,
        Err(_) => return (0, 0),
    };

    let mut unique_days: BTreeSet<NaiveDate> = BTreeSet::new();
    if let Ok(rows) = stmt.query_map(params![profile_id], |row| row.get::<_, String>(0)) {
        for r in rows.flatten() {
            let date_part = r.get(0..10).unwrap_or("");
            if let Ok(d) = NaiveDate::parse_from_str(date_part, "%Y-%m-%d") {
                unique_days.insert(d);
            }
        }
    }

    if unique_days.is_empty() {
        return (0, 0);
    }

    let days: Vec<NaiveDate> = unique_days.into_iter().collect();
    let mut longest = 1;
    let mut run = 1;
    for w in days.windows(2) {
        if (w[1] - w[0]).num_days() == 1 {
            run += 1;
            if run > longest {
                longest = run;
            }
        } else {
            run = 1;
        }
    }

    let today_date = NaiveDate::parse_from_str(today, "%Y-%m-%d")
        .unwrap_or_else(|_| Local::now().date_naive());
    let last_day = *days.last().unwrap();
    let current = if (today_date - last_day).num_days() <= 1 {
        let mut cur = 1;
        for i in (1..days.len()).rev() {
            if (days[i] - days[i - 1]).num_days() == 1 {
                cur += 1;
            } else {
                break;
            }
        }
        cur
    } else {
        0
    };

    (current, longest)
}

pub fn get_dashboard_summary(
    conn: &Connection,
    profile_id: &str,
    date_key_opt: Option<&str>,
) -> Result<DashboardSummary, String> {
    let profile = get_profile(conn, profile_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Profile not found".to_string())?;
    let today_str = date_key_opt
        .map(|s| s.to_string())
        .unwrap_or_else(today_key);

    let today: DailyActivityEntry = conn
        .query_row(
            "SELECT date_key, steps, calories, minutes, workouts_count, updated_at
             FROM daily_activity WHERE profile_id = ?1 AND date_key = ?2",
            params![profile_id, today_str],
            |row| {
                Ok(DailyActivityEntry {
                    date_key: row.get(0)?,
                    steps: row.get(1)?,
                    calories: row.get(2)?,
                    minutes: row.get(3)?,
                    workouts_count: row.get(4)?,
                    updated_at: row.get(5)?,
                })
            },
        )
        .optional()
        .map_err(|e| e.to_string())?
        .unwrap_or(DailyActivityEntry {
            date_key: today_str.clone(),
            steps: 0,
            calories: 0,
            minutes: 0,
            workouts_count: 0,
            updated_at: now_iso(),
        });

    let daily_history =
        get_daily_activity_history(conn, profile_id, 30).map_err(|e| e.to_string())?;
    let weight_history =
        get_body_metric_history(conn, profile_id, "weight", 30).map_err(|e| e.to_string())?;
    let waist_history =
        get_body_metric_history(conn, profile_id, "waist", 30).map_err(|e| e.to_string())?;
    let sleep_history =
        get_body_metric_history(conn, profile_id, "sleep", 30).map_err(|e| e.to_string())?;
    let (current_streak, longest_streak) = compute_streaks(conn, profile_id, &today_str);

    let total_workouts: i32 = conn
        .query_row(
            "SELECT COUNT(*) FROM completed_workouts WHERE profile_id = ?1 AND is_cheated = 0",
            params![profile_id],
            |row| row.get(0),
        )
        .unwrap_or(0);

    let recent_workouts =
        get_completed_workouts(conn, profile_id, 10).map_err(|e| e.to_string())?;

    let latest_photo_path: Option<String> = conn
        .query_row(
            "SELECT file_path FROM progress_photos WHERE profile_id = ?1 ORDER BY taken_at DESC LIMIT 1",
            params![profile_id],
            |row| row.get(0),
        )
        .optional()
        .unwrap_or(None);

    Ok(DashboardSummary {
        profile,
        today,
        daily_history,
        weight_history,
        waist_history,
        sleep_history,
        current_streak,
        longest_streak,
        total_workouts,
        recent_workouts,
        latest_photo_path,
    })
}
