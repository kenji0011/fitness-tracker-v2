pub mod db;
pub mod models;

use rusqlite::Connection;
use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Mutex, OnceLock};

use crate::models::*;

static DB_CONN: OnceLock<Mutex<Option<Connection>>> = OnceLock::new();

fn db_slot() -> &'static Mutex<Option<Connection>> {
    DB_CONN.get_or_init(|| Mutex::new(None))
}

fn dispatch_inner(method: &str, payload: Value) -> Result<Value, String> {
    if method == "init_db" {
        let path = payload["dbPath"]
            .as_str()
            .ok_or_else(|| "dbPath is required".to_string())?;
        let conn = if path == ":memory:" {
            Connection::open_in_memory().map_err(|e| e.to_string())?
        } else {
            if let Some(parent) = std::path::Path::new(path).parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            Connection::open(path).map_err(|e| e.to_string())?
        };
        db::init_schema(&conn).map_err(|e| e.to_string())?;
        let mut guard = db_slot().lock().map_err(|_| "DB lock poisoned".to_string())?;
        *guard = Some(conn);
        return Ok(json!({ "initialized": true }));
    }

    if method == "health_check" {
        return Ok(json!({ "engine": "tempo_core_rust", "sqlite": rusqlite::version() }));
    }

    let mut guard = db_slot().lock().map_err(|_| "DB lock poisoned".to_string())?;
    let conn = guard
        .as_mut()
        .ok_or_else(|| "Database not initialized. Call init_db first.".to_string())?;

    match method {
        "list_profiles" => {
            let list = db::list_profiles(conn).map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }
        "get_profile" => {
            let id = payload["id"].as_str().ok_or("id is required")?;
            let profile = db::get_profile(conn, id).map_err(|e| e.to_string())?;
            serde_json::to_value(profile).map_err(|e| e.to_string())
        }
        "create_profile" => {
            let input: CreateProfileInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let profile = db::create_profile(conn, input)?;
            serde_json::to_value(profile).map_err(|e| e.to_string())
        }
        "verify_pin" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let pin = payload["pin"].as_str().ok_or("pin is required")?;
            let ok = db::verify_pin(conn, profile_id, pin)?;
            Ok(json!({ "valid": ok }))
        }
        "update_profile_pin" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let current_pin = payload["currentPin"].as_str().ok_or("currentPin is required")?;
            let new_pin = payload["newPin"].as_str().ok_or("newPin is required")?;
            let ok = db::update_profile_pin(conn, profile_id, current_pin, new_pin)?;
            Ok(json!({ "updated": ok }))
        }
        "update_profile" => {
            let input: UpdateProfileInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let profile = db::update_profile(conn, input)?;
            serde_json::to_value(profile).map_err(|e| e.to_string())
        }
        "delete_profile" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let deleted = db::delete_profile(conn, profile_id)?;
            Ok(json!({ "deleted": deleted }))
        }
        "get_setting" => {
            let key = payload["key"].as_str().ok_or("key is required")?;
            let val = db::get_setting(conn, key).map_err(|e| e.to_string())?;
            Ok(json!({ "value": val }))
        }
        "set_setting" => {
            let key = payload["key"].as_str().ok_or("key is required")?;
            let value = payload["value"].as_str().ok_or("value is required")?;
            db::set_setting(conn, key, value).map_err(|e| e.to_string())?;
            Ok(json!({ "saved": true }))
        }
        "get_dashboard_summary" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let date_key = payload["dateKey"].as_str();
            let summary = db::get_dashboard_summary(conn, profile_id, date_key)?;
            serde_json::to_value(summary).map_err(|e| e.to_string())
        }
        "upsert_daily_activity" => {
            let input: UpsertDailyActivityInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let entry = db::upsert_daily_activity(conn, input)?;
            serde_json::to_value(entry).map_err(|e| e.to_string())
        }
        "get_daily_activity_history" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let limit = payload["limit"].as_i64().unwrap_or(30) as i32;
            let entries =
                db::get_daily_activity_history(conn, profile_id, limit).map_err(|e| e.to_string())?;
            serde_json::to_value(entries).map_err(|e| e.to_string())
        }
        "log_body_metric" => {
            let input: LogBodyMetricInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let profile = db::log_body_metric(conn, input)?;
            serde_json::to_value(profile).map_err(|e| e.to_string())
        }
        "get_body_metric_history" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let metric_type = payload["metricType"].as_str().ok_or("metricType is required")?;
            let limit = payload["limit"].as_i64().unwrap_or(60) as i32;
            let pts = db::get_body_metric_history(conn, profile_id, metric_type, limit)
                .map_err(|e| e.to_string())?;
            serde_json::to_value(pts).map_err(|e| e.to_string())
        }
        "log_completed_workout" => {
            let input: LogCompletedWorkoutInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let item = db::log_completed_workout(conn, input)?;
            serde_json::to_value(item).map_err(|e| e.to_string())
        }
        "get_completed_workouts" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let limit = payload["limit"].as_i64().unwrap_or(200) as i32;
            let list =
                db::get_completed_workouts(conn, profile_id, limit).map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }
        "log_exercise_record" => {
            let input: LogExerciseRecordInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let rec = db::log_exercise_record(conn, input)?;
            serde_json::to_value(rec).map_err(|e| e.to_string())
        }
        "get_exercise_records" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let exercise_name = payload["exerciseName"].as_str();
            let list = db::get_exercise_records(conn, profile_id, exercise_name)
                .map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }
        "upsert_journey_progress" => {
            let rec: JourneyProgressRecord =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let saved = db::upsert_journey_progress(conn, rec)?;
            serde_json::to_value(saved).map_err(|e| e.to_string())
        }
        "get_journey_progress" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let journey_id = payload["journeyId"].as_str();
            let list = db::get_journey_progress(conn, profile_id, journey_id)
                .map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }
        "add_progress_photo" => {
            let input: AddProgressPhotoInput =
                serde_json::from_value(payload).map_err(|e| e.to_string())?;
            let photo = db::add_progress_photo(conn, input)?;
            serde_json::to_value(photo).map_err(|e| e.to_string())
        }
        "list_progress_photos" => {
            let profile_id = payload["profileId"].as_str().ok_or("profileId is required")?;
            let list = db::list_progress_photos(conn, profile_id).map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }
        "delete_progress_photo" => {
            let photo_id = payload["photoId"].as_str().ok_or("photoId is required")?;
            let deleted = db::delete_progress_photo(conn, photo_id)?;
            Ok(json!({ "deleted": deleted }))
        }
        _ => Err(format!("Unknown method: {}", method)),
    }
}

/// Primary C-ABI entrypoint invoked by Flutter via dart:ffi.
/// Caller MUST release returned pointer using `tempo_free_string`.
#[no_mangle]
pub extern "C" fn tempo_dispatch(
    method_ptr: *const c_char,
    payload_ptr: *const c_char,
) -> *mut c_char {
    let response = (|| -> Value {
        if method_ptr.is_null() {
            return json!({ "ok": false, "error": "Null method pointer" });
        }
        let method = unsafe { CStr::from_ptr(method_ptr) }
            .to_str()
            .unwrap_or("");
        let payload_str = if payload_ptr.is_null() {
            "{}"
        } else {
            unsafe { CStr::from_ptr(payload_ptr) }
                .to_str()
                .unwrap_or("{}")
        };
        let payload: Value = match serde_json::from_str(payload_str) {
            Ok(v) => v,
            Err(e) => return json!({ "ok": false, "error": format!("Invalid JSON payload: {}", e) }),
        };

        match dispatch_inner(method, payload) {
            Ok(data) => json!({ "ok": true, "data": data }),
            Err(err) => json!({ "ok": false, "error": err }),
        }
    })();

    let serialized = serde_json::to_string(&response)
        .unwrap_or_else(|_| r#"{"ok":false,"error":"Serialization failure"}"#.to_string());
    CString::new(serialized)
        .unwrap_or_else(|_| CString::new(r#"{"ok":false,"error":"CString failure"}"#).unwrap())
        .into_raw()
}

#[no_mangle]
pub extern "C" fn tempo_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(method: &str, payload: Value) -> Value {
        let m = CString::new(method).unwrap();
        let p = CString::new(payload.to_string()).unwrap();
        let ptr = tempo_dispatch(m.as_ptr(), p.as_ptr());
        let out = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        tempo_free_string(ptr);
        serde_json::from_str(&out).unwrap()
    }

    #[test]
    fn test_multi_profile_isolation_and_pin() {
        let init = call("init_db", json!({ "dbPath": ":memory:" }));
        assert_eq!(init["ok"], true);

        // Create Profile A with 4-digit PIN
        let p1 = call(
            "create_profile",
            json!({
                "displayName": "Alex",
                "pin": "1234",
                "heightCm": 175.0,
                "weightKg": 70.0,
                "hasCompletedProfile": true
            }),
        );
        assert_eq!(p1["ok"], true);
        let p1_id = p1["data"]["id"].as_str().unwrap().to_string();
        assert_eq!(p1["data"]["bmi"].as_f64().unwrap(), 22.9);

        // Create Profile B with different PIN
        let p2 = call(
            "create_profile",
            json!({
                "displayName": "Jamie",
                "pin": "9876",
                "heightCm": 165.0,
                "weightKg": 60.0,
                "hasCompletedProfile": true
            }),
        );
        assert_eq!(p2["ok"], true);
        let p2_id = p2["data"]["id"].as_str().unwrap().to_string();

        // Verify PIN checks
        assert_eq!(
            call("verify_pin", json!({ "profileId": p1_id, "pin": "1234" }))["data"]["valid"],
            true
        );
        assert_eq!(
            call("verify_pin", json!({ "profileId": p1_id, "pin": "0000" }))["data"]["valid"],
            false
        );

        // Log workout and metrics for Profile A only
        let w = call(
            "log_completed_workout",
            json!({
                "profileId": p1_id,
                "workoutId": "w1",
                "title": "HIIT Blast",
                "actualDurationSec": 1800,
                "caloriesBurned": 320,
                "dateKey": "2026-11-19",
                "completedAt": "2026-11-19T08:00:00Z"
            }),
        );
        assert_eq!(w["ok"], true);

        let sum1 = call(
            "get_dashboard_summary",
            json!({ "profileId": p1_id, "dateKey": "2026-11-19" }),
        );
        let sum2 = call(
            "get_dashboard_summary",
            json!({ "profileId": p2_id, "dateKey": "2026-11-19" }),
        );
        assert_eq!(sum1["data"]["today"]["calories"], 320);
        assert_eq!(sum1["data"]["today"]["workoutsCount"], 1);
        assert_eq!(sum1["data"]["totalWorkouts"], 1);
        assert_eq!(sum2["data"]["today"]["calories"], 0);
        assert_eq!(sum2["data"]["totalWorkouts"], 0);

        // Cascade delete Profile A
        let del = call("delete_profile", json!({ "profileId": p1_id }));
        assert_eq!(del["data"]["deleted"], true);
        let remaining = call("list_profiles", json!({}));
        assert_eq!(remaining["data"].as_array().unwrap().len(), 1);
    }
}
