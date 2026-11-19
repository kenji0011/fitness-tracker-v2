use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub id: String,
    pub display_name: String,
    pub avatar_path: String,
    pub has_pin: bool,
    pub gender: String,
    pub birthdate: String,
    pub age: i32,
    pub height_cm: f64,
    pub weight_kg: f64,
    pub waist_cm: f64,
    pub sleep_hours: f64,
    pub bmi: f64,
    pub fitness_goal: String,
    pub selected_journey_id: String,
    pub selected_journey_name: String,
    pub daily_calories_goal: i32,
    pub daily_minutes_goal: i32,
    pub daily_workouts_goal: i32,
    pub daily_steps_goal: i32,
    pub has_completed_profile: bool,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateProfileInput {
    pub display_name: String,
    pub pin: String,
    #[serde(default)]
    pub avatar_path: String,
    #[serde(default)]
    pub gender: String,
    #[serde(default)]
    pub birthdate: String,
    #[serde(default)]
    pub age: i32,
    #[serde(default)]
    pub height_cm: f64,
    #[serde(default)]
    pub weight_kg: f64,
    #[serde(default)]
    pub waist_cm: f64,
    #[serde(default)]
    pub sleep_hours: f64,
    #[serde(default = "default_goal")]
    pub fitness_goal: String,
    #[serde(default = "default_cal_goal")]
    pub daily_calories_goal: i32,
    #[serde(default = "default_min_goal")]
    pub daily_minutes_goal: i32,
    #[serde(default = "default_workouts_goal")]
    pub daily_workouts_goal: i32,
    #[serde(default = "default_steps_goal")]
    pub daily_steps_goal: i32,
    #[serde(default)]
    pub has_completed_profile: bool,
}

fn default_goal() -> String {
    "general_fitness".to_string()
}
fn default_cal_goal() -> i32 {
    2500
}
fn default_min_goal() -> i32 {
    60
}
fn default_workouts_goal() -> i32 {
    3
}
fn default_steps_goal() -> i32 {
    10000
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProfileInput {
    pub id: String,
    pub display_name: Option<String>,
    pub avatar_path: Option<String>,
    pub gender: Option<String>,
    pub birthdate: Option<String>,
    pub age: Option<i32>,
    pub height_cm: Option<f64>,
    pub weight_kg: Option<f64>,
    pub waist_cm: Option<f64>,
    pub sleep_hours: Option<f64>,
    pub fitness_goal: Option<String>,
    pub selected_journey_id: Option<String>,
    pub selected_journey_name: Option<String>,
    pub daily_calories_goal: Option<i32>,
    pub daily_minutes_goal: Option<i32>,
    pub daily_workouts_goal: Option<i32>,
    pub daily_steps_goal: Option<i32>,
    pub has_completed_profile: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyActivityEntry {
    pub date_key: String,
    pub steps: i32,
    pub calories: i32,
    pub minutes: i32,
    pub workouts_count: i32,
    pub updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertDailyActivityInput {
    pub profile_id: String,
    pub date_key: String,
    pub steps: Option<i32>,
    pub calories: Option<i32>,
    pub minutes: Option<i32>,
    pub workouts_count: Option<i32>,
    #[serde(default)]
    pub increment: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BodyMetricPoint {
    pub id: i64,
    pub metric_type: String,
    pub value: f64,
    pub recorded_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogBodyMetricInput {
    pub profile_id: String,
    pub metric_type: String, // "weight" | "waist" | "sleep" | "height"
    pub value: f64,
    pub recorded_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletedWorkout {
    pub id: String,
    pub profile_id: String,
    pub workout_id: String,
    pub title: String,
    pub duration_label: String,
    pub exercises_label: String,
    pub level: String,
    pub body_focus: String,
    pub journey_id: String,
    pub journey_name: String,
    pub actual_duration_sec: i32,
    pub expected_duration_sec: i32,
    pub calories_burned: i32,
    pub is_cheated: bool,
    pub completed_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogCompletedWorkoutInput {
    pub profile_id: String,
    pub workout_id: String,
    pub title: String,
    #[serde(default)]
    pub duration_label: String,
    #[serde(default)]
    pub exercises_label: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub body_focus: String,
    #[serde(default)]
    pub journey_id: String,
    #[serde(default)]
    pub journey_name: String,
    #[serde(default)]
    pub actual_duration_sec: i32,
    #[serde(default)]
    pub expected_duration_sec: i32,
    #[serde(default)]
    pub calories_burned: i32,
    #[serde(default)]
    pub is_cheated: bool,
    pub completed_at: Option<String>,
    pub date_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExerciseRecordItem {
    pub id: i64,
    pub profile_id: String,
    pub exercise_name: String,
    pub workout_id: String,
    pub weight_used: f64,
    pub reps_performed: i32,
    pub sets_performed: i32,
    pub body_focus: String,
    pub level: String,
    pub journey_id: String,
    pub journey_name: String,
    pub primary_goal: String,
    pub goal_tags: Vec<String>,
    pub recorded_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogExerciseRecordInput {
    pub profile_id: String,
    pub exercise_name: String,
    #[serde(default)]
    pub workout_id: String,
    #[serde(default)]
    pub weight_used: f64,
    #[serde(default)]
    pub reps_performed: i32,
    #[serde(default)]
    pub sets_performed: i32,
    #[serde(default)]
    pub body_focus: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub journey_id: String,
    #[serde(default)]
    pub journey_name: String,
    #[serde(default)]
    pub primary_goal: String,
    #[serde(default)]
    pub goal_tags: Vec<String>,
    pub recorded_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JourneyProgressRecord {
    pub profile_id: String,
    pub journey_id: String,
    pub journey_name: String,
    pub is_selected: bool,
    pub is_completed: bool,
    pub completed_workouts_count: i32,
    pub cheated_workouts_count: i32,
    pub clean_workouts_count: i32,
    pub total_workouts_count: i32,
    pub completion_count: i32,
    pub progress_percent: f64,
    pub status: String,
    pub started_at: Option<String>,
    pub active_cycle_started_at: Option<String>,
    pub completed_at: Option<String>,
    pub next_workout_id: Option<String>,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressPhoto {
    pub id: String,
    pub profile_id: String,
    pub file_path: String,
    pub caption: String,
    pub category: String,
    pub weight_kg: Option<f64>,
    pub taken_at: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddProgressPhotoInput {
    pub profile_id: String,
    pub file_path: String,
    #[serde(default)]
    pub caption: String,
    #[serde(default = "default_photo_category")]
    pub category: String,
    pub weight_kg: Option<f64>,
    pub taken_at: Option<String>,
}

fn default_photo_category() -> String {
    "General".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardSummary {
    pub profile: Profile,
    pub today: DailyActivityEntry,
    pub daily_history: Vec<DailyActivityEntry>,
    pub weight_history: Vec<BodyMetricPoint>,
    pub waist_history: Vec<BodyMetricPoint>,
    pub sleep_history: Vec<BodyMetricPoint>,
    pub current_streak: i32,
    pub longest_streak: i32,
    pub total_workouts: i32,
    pub recent_workouts: Vec<CompletedWorkout>,
    pub latest_photo_path: Option<String>,
}
