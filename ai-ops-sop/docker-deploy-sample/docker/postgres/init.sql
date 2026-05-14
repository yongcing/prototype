-- AIOps Platform — Full Schema
-- Run this on a fresh database (after CREATE EXTENSION vector).
-- Safe to re-run: all statements use IF NOT EXISTS.

CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- users
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id                  BIGSERIAL                    PRIMARY KEY,
    username            VARCHAR(150)                 NOT NULL UNIQUE,
    email               VARCHAR(255)                 NOT NULL UNIQUE,
    display_name        VARCHAR(150),
    hashed_password     VARCHAR(255)                 NOT NULL,
    is_active           BOOLEAN                      NOT NULL DEFAULT TRUE,
    is_superuser        BOOLEAN                      NOT NULL DEFAULT FALSE,
    roles               TEXT                         NOT NULL DEFAULT '[]',
    oidc_provider       VARCHAR(40),
    oidc_sub            VARCHAR(255),
    last_login_at       TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ix_users_username ON users (username);
CREATE UNIQUE INDEX IF NOT EXISTS ix_users_email    ON users (email);

-- ============================================================
-- user_preferences
-- ============================================================
CREATE TABLE IF NOT EXISTS user_preferences (
    id              BIGSERIAL                    PRIMARY KEY,
    user_id         BIGINT                       NOT NULL UNIQUE,
    preferences     TEXT,
    soul_override   TEXT,
    created_at      TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at      TIMESTAMP WITH TIME ZONE     NOT NULL
);

-- ============================================================
-- role_change_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS role_change_logs (
    id              BIGSERIAL                    PRIMARY KEY,
    target_user_id  BIGINT                       NOT NULL,
    actor_user_id   BIGINT,
    old_roles       TEXT                         NOT NULL,
    new_roles       TEXT                         NOT NULL,
    reason          TEXT,
    changed_at      TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_rcl_target     ON role_change_logs (target_user_id);
CREATE INDEX IF NOT EXISTS ix_rcl_changed_at ON role_change_logs (changed_at);

-- ============================================================
-- items
-- ============================================================
CREATE TABLE IF NOT EXISTS items (
    id          BIGSERIAL                    PRIMARY KEY,
    title       VARCHAR(255)                 NOT NULL,
    description TEXT,
    is_active   BOOLEAN                      NOT NULL DEFAULT TRUE,
    owner_id    BIGINT                       NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_items_owner_id ON items (owner_id);

-- ============================================================
-- system_parameters
-- ============================================================
CREATE TABLE IF NOT EXISTS system_parameters (
    id          BIGSERIAL                    PRIMARY KEY,
    key         VARCHAR(100)                 NOT NULL UNIQUE,
    value       TEXT,
    description VARCHAR(500),
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

-- ============================================================
-- audit_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id           BIGSERIAL                    PRIMARY KEY,
    user_id      BIGINT,
    username     VARCHAR(150),
    roles        VARCHAR(100),
    http_method  VARCHAR(10)                  NOT NULL,
    endpoint     VARCHAR(300)                 NOT NULL,
    status_code  INTEGER,
    duration_ms  BIGINT,
    remote_ip    VARCHAR(45),
    user_agent   VARCHAR(500),
    request_body TEXT,
    error_message TEXT,
    created_at   TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_audit_logs_created_at ON audit_logs (created_at);
CREATE INDEX IF NOT EXISTS ix_audit_logs_user_id    ON audit_logs (user_id);
CREATE INDEX IF NOT EXISTS ix_audit_logs_endpoint   ON audit_logs (endpoint);

-- ============================================================
-- event_types
-- ============================================================
CREATE TABLE IF NOT EXISTS event_types (
    id                  BIGSERIAL                    PRIMARY KEY,
    name                VARCHAR(200)                 NOT NULL UNIQUE,
    description         TEXT                         NOT NULL DEFAULT '',
    source              VARCHAR(50)                  NOT NULL DEFAULT 'simulator',
    is_active           BOOLEAN                      NOT NULL DEFAULT TRUE,
    attributes          TEXT                         NOT NULL DEFAULT '[]',
    diagnosis_skill_ids TEXT                         NOT NULL DEFAULT '[]',
    created_at          TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE     NOT NULL
);

-- ============================================================
-- generated_events
-- ============================================================
CREATE TABLE IF NOT EXISTS generated_events (
    id                      BIGSERIAL                    PRIMARY KEY,
    event_type_id           BIGINT                       NOT NULL,
    source_skill_id         BIGINT                       NOT NULL,
    source_routine_check_id BIGINT,
    mapped_parameters       TEXT                         NOT NULL DEFAULT '{}',
    skill_conclusion        TEXT,
    status                  VARCHAR(20)                  NOT NULL DEFAULT 'pending',
    created_at              TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at              TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_generated_events_event_type_id ON generated_events (event_type_id);
CREATE INDEX IF NOT EXISTS ix_generated_events_status        ON generated_events (status);

-- ============================================================
-- nats_event_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS nats_event_logs (
    id              BIGSERIAL                    PRIMARY KEY,
    event_type_name VARCHAR(100)                 NOT NULL,
    equipment_id    VARCHAR(100),
    lot_id          VARCHAR(100),
    payload         TEXT,
    received_at     TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_nats_event_logs_event_type_name ON nats_event_logs (event_type_name);

-- ============================================================
-- data_subjects
-- ============================================================
CREATE TABLE IF NOT EXISTS data_subjects (
    id           BIGSERIAL                    PRIMARY KEY,
    name         VARCHAR(200)                 NOT NULL UNIQUE,
    description  TEXT                         NOT NULL DEFAULT '',
    api_config   TEXT                         NOT NULL DEFAULT '{}',
    input_schema TEXT                         NOT NULL DEFAULT '{}',
    output_schema TEXT                        NOT NULL DEFAULT '{}',
    is_builtin   BOOLEAN                      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at   TIMESTAMP WITH TIME ZONE     NOT NULL
);

-- ============================================================
-- mcp_definitions
-- ============================================================
CREATE TABLE IF NOT EXISTS mcp_definitions (
    id                  BIGSERIAL                    PRIMARY KEY,
    name                VARCHAR(200)                 NOT NULL UNIQUE,
    description         TEXT                         NOT NULL DEFAULT '',
    mcp_type            VARCHAR(10)                  NOT NULL DEFAULT 'custom',
    api_config          TEXT,
    input_schema        TEXT,
    system_mcp_id       BIGINT,
    data_subject_id     BIGINT,
    processing_intent   TEXT                         NOT NULL DEFAULT '',
    processing_script   TEXT,
    output_schema       TEXT,
    ui_render_config    TEXT,
    input_definition    TEXT,
    sample_output       TEXT,
    prefer_over_system  BOOLEAN                      NOT NULL DEFAULT FALSE,
    visibility          VARCHAR(10)                  NOT NULL DEFAULT 'private',
    created_at          TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_mcp_definitions_system_mcp_id   ON mcp_definitions (system_mcp_id);
CREATE INDEX IF NOT EXISTS ix_mcp_definitions_data_subject_id ON mcp_definitions (data_subject_id);

-- ============================================================
-- mock_data_sources
-- ============================================================
CREATE TABLE IF NOT EXISTS mock_data_sources (
    id           BIGSERIAL                    PRIMARY KEY,
    name         VARCHAR(200)                 NOT NULL UNIQUE,
    description  TEXT                         NOT NULL DEFAULT '',
    input_schema TEXT,
    python_code  TEXT,
    sample_output TEXT,
    is_active    BOOLEAN                      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at   TIMESTAMP WITH TIME ZONE     NOT NULL
);

-- ============================================================
-- notification_inbox
-- ============================================================
CREATE TABLE IF NOT EXISTS notification_inbox (
    id         BIGSERIAL                    PRIMARY KEY,
    user_id    BIGINT                       NOT NULL,
    rule_id    BIGINT,
    payload    TEXT                         NOT NULL,
    read_at    TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_notification_inbox_user_recent ON notification_inbox (user_id, created_at);

-- ============================================================
-- skill_documents
-- ============================================================
CREATE TABLE IF NOT EXISTS skill_documents (
    id             BIGSERIAL                    PRIMARY KEY,
    slug           VARCHAR(120)                 NOT NULL UNIQUE,
    title          VARCHAR(200)                 NOT NULL,
    version        VARCHAR(20)                  NOT NULL DEFAULT '0.1',
    stage          VARCHAR(20)                  NOT NULL,
    domain         VARCHAR(80)                  NOT NULL DEFAULT '',
    description    TEXT                         NOT NULL DEFAULT '',
    author_user_id BIGINT,
    certified_by   VARCHAR(120),
    status         VARCHAR(20)                  NOT NULL DEFAULT 'draft',
    trigger_config TEXT                         NOT NULL DEFAULT '{}',
    steps          TEXT                         NOT NULL DEFAULT '[]',
    test_cases     TEXT                         NOT NULL DEFAULT '[]',
    stats          TEXT                         NOT NULL DEFAULT '{}',
    confirm_check  TEXT,
    created_at     TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at     TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_skill_documents_stage  ON skill_documents (stage);
CREATE INDEX IF NOT EXISTS ix_skill_documents_status ON skill_documents (status);
CREATE INDEX IF NOT EXISTS ix_skill_documents_author ON skill_documents (author_user_id);

-- ============================================================
-- skill_definitions
-- ============================================================
CREATE TABLE IF NOT EXISTS skill_definitions (
    id                      BIGSERIAL                    PRIMARY KEY,
    name                    VARCHAR(200)                 NOT NULL UNIQUE,
    description             TEXT                         NOT NULL DEFAULT '',
    trigger_event_id        BIGINT,
    trigger_mode            VARCHAR(20)                  NOT NULL DEFAULT 'both',
    steps_mapping           TEXT                         NOT NULL DEFAULT '[]',
    input_schema            TEXT                         DEFAULT '[]',
    output_schema           TEXT                         DEFAULT '[]',
    pipeline_config         TEXT,
    source                  VARCHAR(20)                  NOT NULL DEFAULT 'legacy',
    binding_type            VARCHAR(20)                  NOT NULL DEFAULT 'none',
    auto_check_description  TEXT                         NOT NULL DEFAULT '',
    visibility              VARCHAR(10)                  NOT NULL DEFAULT 'private',
    trigger_patrol_id       BIGINT,
    created_by              BIGINT,
    is_active               BOOLEAN                      NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at              TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_skill_definitions_trigger_event_id  ON skill_definitions (trigger_event_id);
CREATE INDEX IF NOT EXISTS ix_skill_definitions_trigger_patrol_id ON skill_definitions (trigger_patrol_id);

-- ============================================================
-- script_versions
-- ============================================================
CREATE TABLE IF NOT EXISTS script_versions (
    id               BIGSERIAL                    PRIMARY KEY,
    skill_id         BIGINT                       NOT NULL,
    version          INTEGER                      NOT NULL DEFAULT 1,
    status           VARCHAR(20)                  NOT NULL DEFAULT 'draft',
    code             TEXT                         NOT NULL,
    change_note      TEXT,
    reviewed_by      VARCHAR(100),
    approved_at      TIMESTAMP WITH TIME ZONE,
    generated_at     TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_script_versions_skill_id ON script_versions (skill_id);
CREATE INDEX IF NOT EXISTS ix_script_versions_status   ON script_versions (status);

-- ============================================================
-- routine_checks
-- ============================================================
CREATE TABLE IF NOT EXISTS routine_checks (
    id                   BIGSERIAL                    PRIMARY KEY,
    name                 VARCHAR(200)                 NOT NULL,
    skill_id             BIGINT                       NOT NULL,
    preset_parameters    TEXT                         NOT NULL DEFAULT '{}',
    trigger_event_id     BIGINT,
    event_param_mappings TEXT,
    schedule_interval    VARCHAR(20)                  NOT NULL DEFAULT '1h',
    is_active            BOOLEAN                      NOT NULL DEFAULT TRUE,
    last_run_at          TEXT,
    last_run_status      VARCHAR(20),
    expire_at            TEXT,
    schedule_time        VARCHAR(5),
    created_at           TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at           TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_routine_checks_skill_id ON routine_checks (skill_id);
CREATE INDEX IF NOT EXISTS ix_routine_checks_name     ON routine_checks (name);

-- ============================================================
-- cron_jobs
-- ============================================================
CREATE TABLE IF NOT EXISTS cron_jobs (
    id          BIGSERIAL                    PRIMARY KEY,
    skill_id    BIGINT                       NOT NULL,
    schedule    VARCHAR(100)                 NOT NULL,
    timezone    VARCHAR(50)                  NOT NULL DEFAULT 'Asia/Taipei',
    label       VARCHAR(200)                 NOT NULL DEFAULT '',
    status      VARCHAR(20)                  NOT NULL DEFAULT 'active',
    created_by  VARCHAR(100),
    last_run_at TIMESTAMP WITH TIME ZONE,
    next_run_at TIMESTAMP WITH TIME ZONE,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_cron_jobs_skill_id ON cron_jobs (skill_id);
CREATE INDEX IF NOT EXISTS ix_cron_jobs_status   ON cron_jobs (status);

-- ============================================================
-- execution_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS execution_logs (
    id               BIGSERIAL                    PRIMARY KEY,
    skill_id         BIGINT                       NOT NULL,
    auto_patrol_id   BIGINT,
    script_version_id BIGINT,
    cron_job_id      BIGINT,
    triggered_by     VARCHAR(80)                  NOT NULL DEFAULT 'manual',
    event_context    TEXT,
    status           VARCHAR(20)                  NOT NULL DEFAULT 'success',
    llm_readable_data TEXT,
    action_dispatched VARCHAR(50),
    error_message    TEXT,
    started_at       TIMESTAMP WITH TIME ZONE     NOT NULL,
    finished_at      TIMESTAMP WITH TIME ZONE,
    duration_ms      BIGINT
);

CREATE INDEX IF NOT EXISTS ix_execution_logs_skill_id       ON execution_logs (skill_id);
CREATE INDEX IF NOT EXISTS ix_execution_logs_auto_patrol_id ON execution_logs (auto_patrol_id);
CREATE INDEX IF NOT EXISTS ix_execution_logs_cron_job_id    ON execution_logs (cron_job_id);
CREATE INDEX IF NOT EXISTS ix_execution_logs_status         ON execution_logs (status);

-- ============================================================
-- skill_runs
-- ============================================================
CREATE TABLE IF NOT EXISTS skill_runs (
    id              BIGSERIAL                    PRIMARY KEY,
    skill_id        BIGINT                       NOT NULL,
    triggered_at    TIMESTAMP WITH TIME ZONE     NOT NULL,
    triggered_by    VARCHAR(40)                  NOT NULL,
    trigger_payload TEXT                         NOT NULL DEFAULT '{}',
    is_test         BOOLEAN                      NOT NULL DEFAULT FALSE,
    status          VARCHAR(20)                  NOT NULL DEFAULT 'running',
    step_results    TEXT                         NOT NULL DEFAULT '[]',
    duration_ms     INTEGER,
    finished_at     TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS ix_skill_runs_skill ON skill_runs (skill_id, triggered_at);
CREATE INDEX IF NOT EXISTS ix_skill_runs_test  ON skill_runs (skill_id, is_test, triggered_at);

-- ============================================================
-- feedback_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS feedback_logs (
    id                      BIGSERIAL                    PRIMARY KEY,
    target_type             VARCHAR(10)                  NOT NULL,
    target_id               BIGINT                       NOT NULL,
    user_feedback           TEXT                         NOT NULL DEFAULT '',
    previous_result_summary TEXT,
    llm_reflection          TEXT,
    revised_script          TEXT,
    rerun_success           BOOLEAN                      NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_feedback_logs_target_type ON feedback_logs (target_type);
CREATE INDEX IF NOT EXISTS ix_feedback_logs_target_id   ON feedback_logs (target_id);

-- ============================================================
-- alarms
-- ============================================================
CREATE TABLE IF NOT EXISTS alarms (
    id               BIGSERIAL                    PRIMARY KEY,
    skill_id         BIGINT,
    trigger_event    VARCHAR(100)                 NOT NULL DEFAULT '',
    equipment_id     VARCHAR(100)                 NOT NULL DEFAULT '',
    lot_id           VARCHAR(100)                 NOT NULL DEFAULT '',
    step             VARCHAR(50),
    event_time       TIMESTAMP WITH TIME ZONE,
    severity         VARCHAR(20)                  NOT NULL DEFAULT 'MEDIUM',
    title            VARCHAR(300)                 NOT NULL DEFAULT '',
    summary          TEXT,
    status           VARCHAR(20)                  NOT NULL DEFAULT 'active',
    acknowledged_by  VARCHAR(100),
    acknowledged_at  TIMESTAMP WITH TIME ZONE,
    resolved_at      TIMESTAMP WITH TIME ZONE,
    execution_log_id BIGINT,
    diagnostic_log_id BIGINT,
    acked_by         BIGINT,
    acked_at         TIMESTAMP WITH TIME ZONE,
    disposition      VARCHAR(20),
    disposition_reason TEXT,
    disposed_by      BIGINT,
    disposed_at      TIMESTAMP WITH TIME ZONE,
    created_at       TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_alarms_skill_id         ON alarms (skill_id);
CREATE INDEX IF NOT EXISTS ix_alarms_trigger_event    ON alarms (trigger_event);
CREATE INDEX IF NOT EXISTS ix_alarms_equipment_id     ON alarms (equipment_id);
CREATE INDEX IF NOT EXISTS ix_alarms_lot_id           ON alarms (lot_id);
CREATE INDEX IF NOT EXISTS ix_alarms_execution_log_id ON alarms (execution_log_id);

-- ============================================================
-- auto_patrols
-- ============================================================
CREATE TABLE IF NOT EXISTS auto_patrols (
    id                      BIGSERIAL                    PRIMARY KEY,
    name                    VARCHAR(200)                 NOT NULL,
    description             TEXT                         NOT NULL DEFAULT '',
    skill_id                BIGINT,
    skill_doc_id            BIGINT,
    pipeline_id             BIGINT,
    input_binding           TEXT,
    trigger_mode            VARCHAR(20)                  NOT NULL DEFAULT 'schedule',
    event_type_id           BIGINT,
    cron_expr               VARCHAR(100),
    scheduled_at            TIMESTAMP WITH TIME ZONE,
    auto_check_description  TEXT                         NOT NULL DEFAULT '',
    data_context            VARCHAR(100)                 NOT NULL DEFAULT 'recent_ooc',
    target_scope            TEXT                         NOT NULL DEFAULT '{"type":"event_driven"}',
    alarm_severity          VARCHAR(20),
    alarm_title             VARCHAR(300),
    notify_config           TEXT,
    is_active               BOOLEAN                      NOT NULL DEFAULT TRUE,
    created_by              BIGINT,
    kind                    VARCHAR(40)                  NOT NULL DEFAULT 'shared_alarm',
    notification_channels   TEXT,
    notification_template   TEXT,
    last_dispatched_at      TIMESTAMP WITH TIME ZONE,
    created_at              TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at              TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_auto_patrols_skill_id     ON auto_patrols (skill_id);
CREATE INDEX IF NOT EXISTS ix_auto_patrols_pipeline_id  ON auto_patrols (pipeline_id);
CREATE INDEX IF NOT EXISTS ix_auto_patrols_event_type_id ON auto_patrols (event_type_id);
CREATE INDEX IF NOT EXISTS ix_auto_patrols_skill_doc_id ON auto_patrols (skill_doc_id);

-- ============================================================
-- personal_rule_fires
-- ============================================================
CREATE TABLE IF NOT EXISTS personal_rule_fires (
    id        BIGSERIAL                    PRIMARY KEY,
    patrol_id BIGINT                       NOT NULL,
    fired_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    payload   TEXT                         NOT NULL DEFAULT '{}',
    inbox_id  BIGINT
);

CREATE INDEX IF NOT EXISTS ix_personal_rule_fires_rule ON personal_rule_fires (patrol_id, fired_at);

-- ============================================================
-- pb_blocks
-- ============================================================
CREATE TABLE IF NOT EXISTS pb_blocks (
    id                  BIGSERIAL                    PRIMARY KEY,
    name                VARCHAR(128)                 NOT NULL,
    category            VARCHAR(32)                  NOT NULL,
    version             VARCHAR(32)                  NOT NULL DEFAULT '1.0.0',
    status              VARCHAR(16)                  NOT NULL DEFAULT 'draft',
    description         TEXT                         NOT NULL DEFAULT '',
    input_schema        TEXT                         NOT NULL DEFAULT '[]',
    output_schema       TEXT                         NOT NULL DEFAULT '[]',
    param_schema        TEXT                         NOT NULL DEFAULT '{}',
    implementation      TEXT                         NOT NULL DEFAULT '{}',
    examples            TEXT                         NOT NULL DEFAULT '[]',
    output_columns_hint TEXT                         NOT NULL DEFAULT '[]',
    is_custom           BOOLEAN                      NOT NULL DEFAULT FALSE,
    created_by          BIGINT,
    approved_by         BIGINT,
    approved_at         TIMESTAMP WITH TIME ZONE,
    review_note         TEXT,
    created_at          TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE     NOT NULL,
    CONSTRAINT uq_pb_blocks_name_version UNIQUE (name, version)
);

CREATE INDEX IF NOT EXISTS ix_pb_blocks_name ON pb_blocks (name);

-- ============================================================
-- pb_pipelines
-- ============================================================
CREATE TABLE IF NOT EXISTS pb_pipelines (
    id                  BIGSERIAL                    PRIMARY KEY,
    name                VARCHAR(128)                 NOT NULL,
    description         TEXT                         NOT NULL DEFAULT '',
    status              VARCHAR(20)                  NOT NULL DEFAULT 'draft',
    pipeline_kind       VARCHAR(20),
    version             VARCHAR(32)                  NOT NULL DEFAULT '1.0.0',
    pipeline_json       TEXT                         NOT NULL DEFAULT '{}',
    usage_stats         TEXT                         NOT NULL DEFAULT '{"invoke_count":0,"last_invoked_at":null,"last_triggered_at":null}',
    auto_doc            TEXT,
    locked_at           TIMESTAMP WITH TIME ZONE,
    locked_by           TEXT,
    published_at        TIMESTAMP WITH TIME ZONE,
    archived_at         TIMESTAMP WITH TIME ZONE,
    created_by          BIGINT,
    approved_by         BIGINT,
    approved_at         TIMESTAMP WITH TIME ZONE,
    parent_id           BIGINT,
    parent_skill_doc_id BIGINT,
    parent_slot         VARCHAR(40),
    created_at          TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at          TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_pb_pipelines_name ON pb_pipelines (name);

-- ============================================================
-- pb_pipeline_runs
-- ============================================================
CREATE TABLE IF NOT EXISTS pb_pipeline_runs (
    id               BIGSERIAL                    PRIMARY KEY,
    pipeline_id      BIGINT,
    pipeline_version VARCHAR(32)                  NOT NULL DEFAULT 'adhoc',
    triggered_by     VARCHAR(32)                  NOT NULL DEFAULT 'user',
    status           VARCHAR(32)                  NOT NULL DEFAULT 'running',
    node_results     TEXT,
    error_message    TEXT,
    started_at       TIMESTAMP WITH TIME ZONE     NOT NULL,
    finished_at      TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS ix_pb_pipeline_runs_pipeline_id ON pb_pipeline_runs (pipeline_id);
CREATE INDEX IF NOT EXISTS ix_pb_pipeline_runs_status      ON pb_pipeline_runs (status);

-- ============================================================
-- pb_canvas_operations
-- ============================================================
CREATE TABLE IF NOT EXISTS pb_canvas_operations (
    id          BIGSERIAL                    PRIMARY KEY,
    pipeline_id BIGINT,
    actor       VARCHAR(32)                  NOT NULL DEFAULT 'user',
    operation   VARCHAR(32)                  NOT NULL,
    payload     TEXT                         NOT NULL DEFAULT '{}',
    reasoning   TEXT,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_pb_canvas_operations_pipeline_id ON pb_canvas_operations (pipeline_id);

-- ============================================================
-- pb_published_skills
-- ============================================================
CREATE TABLE IF NOT EXISTS pb_published_skills (
    id               BIGSERIAL                    PRIMARY KEY,
    pipeline_id      BIGINT                       NOT NULL,
    pipeline_version VARCHAR(32)                  NOT NULL,
    slug             VARCHAR(80)                  NOT NULL UNIQUE,
    name             VARCHAR(128)                 NOT NULL,
    use_case         TEXT                         NOT NULL DEFAULT '',
    when_to_use      TEXT                         NOT NULL DEFAULT '[]',
    inputs_schema    TEXT                         NOT NULL DEFAULT '[]',
    outputs_schema   TEXT                         NOT NULL DEFAULT '{}',
    example_invocation TEXT,
    tags             TEXT                         NOT NULL DEFAULT '[]',
    status           VARCHAR(16)                  NOT NULL DEFAULT 'active',
    published_by     TEXT,
    published_at     TIMESTAMP WITH TIME ZONE     NOT NULL,
    retired_at       TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uq_pbps_pipeline_version UNIQUE (pipeline_id, pipeline_version)
);

-- ============================================================
-- pipeline_auto_check_triggers
-- ============================================================
CREATE TABLE IF NOT EXISTS pipeline_auto_check_triggers (
    id          BIGSERIAL                    PRIMARY KEY,
    pipeline_id BIGINT                       NOT NULL,
    event_type  VARCHAR(128)                 NOT NULL,
    match_filter TEXT,
    skill_doc_id BIGINT,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    CONSTRAINT uq_pacheck_pipeline_event UNIQUE (pipeline_id, event_type)
);

CREATE INDEX IF NOT EXISTS ix_pipeline_auto_check_triggers_pipeline_id ON pipeline_auto_check_triggers (pipeline_id);
CREATE INDEX IF NOT EXISTS ix_pipeline_auto_check_triggers_event_type  ON pipeline_auto_check_triggers (event_type);
CREATE INDEX IF NOT EXISTS ix_auto_check_skill_doc                      ON pipeline_auto_check_triggers (skill_doc_id);

-- ============================================================
-- agent_sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_sessions (
    session_id           VARCHAR(36)                  NOT NULL PRIMARY KEY,
    user_id              BIGINT                       NOT NULL,
    messages             TEXT                         NOT NULL DEFAULT '[]',
    created_at           TIMESTAMP WITH TIME ZONE     NOT NULL,
    expires_at           TIMESTAMP WITH TIME ZONE,
    cumulative_tokens    INTEGER                      DEFAULT 0,
    workspace_state      TEXT,
    last_pipeline_json   TEXT,
    last_pipeline_run_id BIGINT,
    title                VARCHAR(200),
    updated_at           TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS ix_agent_sessions_user_id ON agent_sessions (user_id);

-- ============================================================
-- agent_drafts
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_drafts (
    id         VARCHAR(36)                  NOT NULL PRIMARY KEY,
    draft_type VARCHAR(20)                  NOT NULL,
    payload    TEXT                         NOT NULL DEFAULT '{}',
    user_id    BIGINT                       NOT NULL,
    status     VARCHAR(10)                  NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_drafts_user_id ON agent_drafts (user_id);

-- ============================================================
-- agent_tools
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_tools (
    id          BIGSERIAL                    PRIMARY KEY,
    user_id     BIGINT                       NOT NULL,
    name        VARCHAR(200)                 NOT NULL,
    code        TEXT                         NOT NULL,
    description TEXT                         NOT NULL DEFAULT '',
    usage_count INTEGER                      NOT NULL DEFAULT 0,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_tools_user_id ON agent_tools (user_id);
CREATE INDEX IF NOT EXISTS ix_agent_tools_name    ON agent_tools (name);

-- ============================================================
-- agent_feedback_log
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_feedback_log (
    id               BIGSERIAL                    PRIMARY KEY,
    session_id       VARCHAR(100)                 NOT NULL,
    user_id          BIGINT                       NOT NULL,
    message_idx      INTEGER                      NOT NULL,
    rating           SMALLINT                     NOT NULL,
    reason           VARCHAR(40),
    free_text        VARCHAR(500),
    contract_summary TEXT,
    tools_used       TEXT,
    created_at       TIMESTAMP WITH TIME ZONE     NOT NULL,
    CONSTRAINT ux_agent_feedback_log_session_message_user UNIQUE (session_id, message_idx, user_id)
);

CREATE INDEX IF NOT EXISTS ix_agent_feedback_log_session    ON agent_feedback_log (session_id);
CREATE INDEX IF NOT EXISTS ix_agent_feedback_log_created_at ON agent_feedback_log (created_at);

-- ============================================================
-- agent_memories
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_memories (
    id           BIGSERIAL                    PRIMARY KEY,
    user_id      BIGINT                       NOT NULL,
    content      TEXT                         NOT NULL,
    embedding    TEXT,
    source       VARCHAR(50),
    ref_id       VARCHAR(100),
    task_type    VARCHAR(100),
    data_subject VARCHAR(200),
    tool_name    VARCHAR(100),
    created_at   TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at   TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_memories_user_id      ON agent_memories (user_id);
CREATE INDEX IF NOT EXISTS ix_agent_memories_task_type    ON agent_memories (task_type);
CREATE INDEX IF NOT EXISTS ix_agent_memories_data_subject ON agent_memories (data_subject);

-- ============================================================
-- agent_directives
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_directives (
    id          BIGSERIAL                    PRIMARY KEY,
    user_id     BIGINT                       NOT NULL,
    scope_type  VARCHAR(20)                  NOT NULL,
    scope_value VARCHAR(120),
    title       VARCHAR(200)                 NOT NULL,
    body        TEXT                         NOT NULL,
    priority    VARCHAR(10)                  NOT NULL DEFAULT 'med',
    active      BOOLEAN                      NOT NULL DEFAULT TRUE,
    source      VARCHAR(20)                  NOT NULL DEFAULT 'manual',
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_directives_user_scope ON agent_directives (user_id, scope_type, scope_value, active);

-- ============================================================
-- agent_directive_fires
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_directive_fires (
    id           BIGSERIAL                    PRIMARY KEY,
    directive_id BIGINT                       NOT NULL,
    fired_at     TIMESTAMP WITH TIME ZONE     NOT NULL,
    session_id   VARCHAR(64),
    context      VARCHAR(200)
);

CREATE INDEX IF NOT EXISTS ix_directive_fires_directive ON agent_directive_fires (directive_id, fired_at);

-- ============================================================
-- agent_lexicon
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_lexicon (
    id         BIGSERIAL                    PRIMARY KEY,
    user_id    BIGINT                       NOT NULL,
    term       VARCHAR(80)                  NOT NULL,
    standard   VARCHAR(120)                 NOT NULL,
    note       TEXT,
    uses       INTEGER                      NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE     NOT NULL,
    CONSTRAINT uq_agent_lexicon_user_term UNIQUE (user_id, term)
);

CREATE INDEX IF NOT EXISTS ix_agent_lexicon_user ON agent_lexicon (user_id);

-- ============================================================
-- agent_knowledge  (requires vector extension)
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_knowledge (
    id          BIGSERIAL                    PRIMARY KEY,
    user_id     BIGINT                       NOT NULL,
    scope_type  VARCHAR(20)                  NOT NULL,
    scope_value VARCHAR(120),
    title       VARCHAR(200)                 NOT NULL,
    body        TEXT                         NOT NULL,
    priority    VARCHAR(10)                  NOT NULL DEFAULT 'med',
    active      BOOLEAN                      NOT NULL DEFAULT TRUE,
    source      VARCHAR(20)                  NOT NULL DEFAULT 'manual',
    embedding   vector(1024),
    uses        INTEGER                      NOT NULL DEFAULT 0,
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_knowledge_user_scope ON agent_knowledge (user_id, scope_type, scope_value, active);

-- ============================================================
-- agent_examples  (requires vector extension)
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_examples (
    id          BIGSERIAL                    PRIMARY KEY,
    user_id     BIGINT                       NOT NULL,
    scope_type  VARCHAR(20)                  NOT NULL,
    scope_value VARCHAR(120),
    title       VARCHAR(200)                 NOT NULL,
    input_text  TEXT                         NOT NULL,
    output_text TEXT                         NOT NULL,
    embedding   vector(1024),
    uses        INTEGER                      NOT NULL DEFAULT 0,
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at  TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_examples_user_scope ON agent_examples (user_id, scope_type, scope_value);

-- ============================================================
-- agent_experience_memory  (requires vector extension)
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_experience_memory (
    id                BIGSERIAL                    PRIMARY KEY,
    user_id           BIGINT                       NOT NULL,
    intent_summary    VARCHAR(500)                 NOT NULL,
    abstract_action   TEXT                         NOT NULL,
    embedding         vector(1024),
    confidence_score  INTEGER                      NOT NULL DEFAULT 5,
    use_count         INTEGER                      NOT NULL DEFAULT 0,
    success_count     INTEGER                      NOT NULL DEFAULT 0,
    fail_count        INTEGER                      NOT NULL DEFAULT 0,
    status            VARCHAR(20)                  NOT NULL DEFAULT 'ACTIVE',
    source            VARCHAR(50)                  NOT NULL DEFAULT 'auto',
    source_session_id VARCHAR(100),
    last_used_at      TIMESTAMP WITH TIME ZONE,
    created_at        TIMESTAMP WITH TIME ZONE     NOT NULL,
    updated_at        TIMESTAMP WITH TIME ZONE     NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_agent_experience_memory_user_id ON agent_experience_memory (user_id);
CREATE INDEX IF NOT EXISTS ix_agent_experience_memory_status  ON agent_experience_memory (status);
