--  This file is part of the eliona project.
--  Copyright © 2022 LEICOM iTEC AG. All Rights Reserved.
--  ______ _ _
-- |  ____| (_)
-- | |__  | |_  ___  _ __   __ _
-- |  __| | | |/ _ \| '_ \ / _` |
-- | |____| | | (_) | | | | (_| |
-- |______|_|_|\___/|_| |_|\__,_|
--
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
--  BUT NOT LIMITED  TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--  NON INFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
--  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-- Use this file to initialize a mocking database. The database have to be PostgreSQL.
-- You can use any cloud service or a docker container to create a local database. An example
-- docker-compose.yml file is also provided in this directory.

create schema if not exists public;

create table if not exists public.asset_type
(
    asset_type         text not null primary key,
    custom             boolean default true not null,
    payload_fct        text,
    vendor             text,
    model              text,
    tracker            boolean default false not null,
    translation        jsonb,
    urldoc             text,
    allowed_inactivity interval,
    iv_asset_type      numeric,
    icon               text,
    type_id            integer default 0 not null
);

create sequence if not exists public.eliona_project_proj_id_seq;

create table public.eliona_project
(
    proj_id     text    default (nextval('eliona_project_proj_id_seq'::regclass))::text not null primary key,
    displayname text                                                                    not null unique,
    location    text,
    email       text,
    regexp      text,
    names       text[],
    icon        text,
    logo        text,
    palette     json,
    logo_big    boolean default false,
    logo_white  boolean default false,
    default_ticket_assignee_id text
);

create extension if not exists ltree;

create table if not exists public.asset
(
    asset_id    serial constraint asset_asset_id_idx primary key,
    proj_id     text
        references public.eliona_project
            on update cascade on delete set null,
    gai         text not null,
    name        text,
    device_pkey text unique,
    asset_type  text,
    lat         double precision,
    lon         double precision,
    storey      smallint,
    description text,
    tags        text[],
    ar          boolean                  default false                        not null,
    urldoc      json,
    created_by  text,
    created_at  timestamp with time zone default now() not null,
    modified_by text,
    modified_at timestamp with time zone default now() not null,
    deleted_by  text,
    deleted_at  timestamp with time zone,
    archived    boolean generated always as ((deleted_at IS NOT NULL)) stored not null,
    tracker_id  integer,
    loc_path  ltree unique,
    func_path ltree unique,
    modified_by_api boolean default false NOT NULL,
    key_access  boolean,
    unique (gai, proj_id)
);

ALTER TABLE public.asset REPLICA IDENTITY FULL;

create table if not exists public.asset_pkey
(
    asset_id integer not null
        references public.asset
            on delete cascade,
    uin      text unique
);

create table if not exists public.attribute_schema
(
    id              serial primary key,
    asset_type      text                          not null,
    attribute_type  text,
    attribute       text                          not null,
    subtype         text    default 'input'::text not null,
    is_digital      boolean default false         not null,
    enable          boolean default true          not null,
    translation     jsonb,
    unit            text,
    formula         text,
    scale           numeric,
    zero            double precision,
    precision       smallint,
    min             numeric,
    max             numeric,
    step            numeric,
    map             json,
    pipeline_mode   text,
    pipeline_raster text[],
    viewer          boolean default false         not null,
    ar              boolean default false         not null,
    seq             smallint,
    source_path     text[],
    virtual         boolean,
    category        text,
    "default"         json,
    unique (asset_type, subtype, attribute)
);

create table if not exists public.heap
(
    asset_id            integer                                not null,
    subtype             text                                   not null,
    his                 boolean                  default true  not null,
    ts                  timestamp with time zone default now() not null,
    data                jsonb,
    valid               boolean,
    allowed_inactivity  interval,
    update_cnt          bigint                   default 1     not null,
    update_cnt_reset_ts timestamp with time zone default now() not null,
    pid                 integer,
    source              text,
    primary key (asset_id, subtype)
);

ALTER TABLE public.heap REPLICA IDENTITY FULL;

CREATE OR REPLACE FUNCTION heap_counter ()
    RETURNS TRIGGER -- before
    LANGUAGE plpgsql
AS $$
BEGIN
    -- Das ist ein reiner update-Trigger.
    -- Das allererste Insert würde, selbst wenn es eine Rasterung hätte, würde hier nicht ankommen.
    -- Insert ... on conflict .. do update schon.
    -- Leider würde dabei ein on insert or update - Trigger zweimal aufgerufen!
    -- Ein After-Trigger hat dieses Problem nicht, der wird nur zweimal markiert und hinterher einmal aufgerufen.
    NEW.update_cnt = NEW.update_cnt + 1;
    NEW.pid        = pg_backend_pid();
    IF (current_query() !~ 'source') THEN
        NEW.source = NULL; -- TODO: reset "source" spec, if not in the update
    END IF;

    RETURN NEW;
END
$$;

-- Kann vielleicht auch mal entfallen.
DROP TRIGGER IF EXISTS heap_counter ON heap;

CREATE TRIGGER heap_counter
    BEFORE UPDATE OF ts ON heap
    FOR EACH ROW
    WHEN (old.ts != new.ts)
EXECUTE PROCEDURE heap_counter ();

create table if not exists public.eliona_app
(
    app_name       text  not null primary key,
    enable         boolean                  default false,
    version        text,
    created_at     timestamp with time zone default now(),
    modified_at    timestamp with time zone,
    initialized_at timestamp with time zone,
    initialised    boolean,
    modified_by    text
);

insert into public.eliona_app (app_name, enable)
values
    ('template', true),
    ('example', true);

create table if not exists public.eliona_store
(
    app_name   text not null primary key,
    category   text,
    version    text not null,
    metadata   json,
    icon       text,
    created_at timestamp with time zone default now(),
    iv_app     numeric,
    repository text default 'internal'::text not null
);

insert into public.eliona_store (app_name, category, version)
values
    ('template', 'app', '1.0.0'),
    ('example', 'app', '1.0.0');

create schema if not exists versioning;

create table if not exists versioning.patches (
                                                  app_name    text                                   not null,
                                                  patch_name  text                                   not null,
                                                  applied_tsz timestamp with time zone default now() not null,
    applied_by  text                                   not null,
    requires    text[],
    conflicts   text[],
    primary key (app_name, patch_name)
    );

create table if not exists public.widget (
                                             id           serial unique,
                                             dashboard_id integer not null,
                                             type_id      integer not null,
                                             seq          smallint,
                                             detail       json,
                                             asset_id     integer,
                                             primary key (dashboard_id, id)
    );

create table if not exists public.widget_data (
                                                  widget_id         integer not null,
                                                  widget_element_id integer not null,
                                                  asset_id          integer,
                                                  data              json,
                                                  id                serial primary key
);

create table if not exists public.widget_type (
                                                  type_id              serial primary key,
                                                  name                 text   not null unique,
                                                  tag                  text,
                                                  translation          jsonb,
                                                  icon                 text,
                                                  custom               boolean default true not null,
                                                  with_alarm           boolean,
                                                  with_timespan_select boolean
);

create table if not exists public.widget_element (
                                                     id       serial primary key,
                                                     type_id  integer not null,
                                                     category text    not null,
                                                     seq      smallint default 0,
                                                     config   json
);

create table if not exists public.alarm
(
    alarm_id    integer                  not null primary key,
    asset_id    integer                  not null,
    subtype     text,
    attribute   text,
    prio        smallint                 not null,
    val         double precision,
    ack_p       boolean                  not null,
    ts          timestamp with time zone not null,
    gone_ts     timestamp with time zone,
    ack_ts      timestamp with time zone,
    multi       integer default 1        not null,
    message     json                     not null,
    ack_text    text,
    ack_user_id text
);

CREATE OR REPLACE FUNCTION alarm_ack_trigger ()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM public.alarm
    WHERE
        alarm_id = OLD.alarm_id
      AND
        gone_ts IS NOT NULL
      AND (
        (ack_p IS FALSE)
            OR
        (ack_p IS TRUE AND ack_ts IS NOT NULL)
        );
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS alarm_ack_trigger ON alarm;
CREATE TRIGGER alarm_ack_trigger
    AFTER UPDATE ON alarm
    FOR EACH ROW
EXECUTE PROCEDURE alarm_ack_trigger ();

create table if not exists public.alarm_cfg
(
    alarm_id    integer generated by default as identity primary key,
    asset_id    integer                                         not null,
    subtype     text                     default 'input'::text  not null,
    attribute   text,
    enable      boolean                  default true           not null,
    prio        smallint                                        not null,
    ack_p       boolean                                         not null,
    auto_ticket boolean                  default false          not null,
    equal       double precision,
    low         double precision,
    high        double precision,
    message     json,
    tags        text[],
    configs     json,
    urldoc      text,
    notify_on   char                     default 'R'::bpchar,
    dont_mask   boolean                  default false          not null,
    created_by  text,
    created_at  timestamp with time zone default now()          not null,
    modified_by text,
    modified_at timestamp with time zone default now()          not null,
    func_id     integer,
    check_type  text                     default 'limits'::text not null,
    ruleengine_id text,
    params      json,
    modified_by_api boolean default false NOT NULL
);

create table if not exists public.alarm_history (
    alarm_id    integer,
    asset_id    integer                  not null,
    subtype     text                     not null,
    attribute   text,
    prio        smallint                 not null,
    val         double precision,
    ack_p       boolean                  not null,
    ts          timestamp with time zone not null,
    gone_ts     timestamp with time zone,
    ack_ts      timestamp with time zone,
    multi       integer                  not null,
    message     json,
    ack_text    text,
    ack_user_id text,
    primary key (ts, asset_id, subtype)
);

create table if not exists public.edge_bridge
(
    bridge_id   integer primary key,
    node_id     text,
    asset_id    integer,
    class       text                  not null,
    description text,
    enable      boolean default false not null,
    config      json
);

create extension if not exists "uuid-ossp";

create table if not exists public.eliona_node
(
    node_id     text    primary key,
    ident       uuid    default uuid_generate_v4()                                   not null        unique,
    password    text,
    asset_id    integer        unique,
    vendor      text,
    model       text,
    description text,
    enable      boolean default false                                                not null
    );

create table if not exists public.iosys_access
(
    id              integer primary key,
    device_id       integer               not null,
    iosvar          text                  not null,
    iostype         text,
    down            boolean default false not null,
    enable          boolean default true  not null,
    asset_id        integer,
    subtype         text                  not null,
    attribute       text                  not null,
    scale           double precision,
    zero            double precision,
    mask            integer[],
    mask_attributes text[],
    dead_time       integer,
    dead_band       double precision,
    filter          text,
    tau             double precision,
    unique (device_id, iosvar)
    );

create table if not exists public.iosys_device
(
    device_id   integer primary key,
    bridge_id   integer                not null,
    enable      boolean  default false not null,
    port        integer,
    certificate text,
    key         text,
    timeout     smallint default 0,
    reconnect   smallint default 30
);

create table if not exists public.mbus_access
(
    id        integer primary key,
    device_id integer              not null,
    field     smallint             not null,
    enable    boolean default true not null,
    asset_id  integer,
    subtype   text,
    attribute text,
    scale     double precision,
    zero      double precision,
    unique (device_id, field),
    unique (asset_id, subtype, attribute)
    );

create table if not exists public.mbus_device
(
    device_id         integer primary key,
    bridge_id         integer                not null,
    manufacturer      text,
    model             text,
    address           smallint,
    sec_address       text,
    enable            boolean  default false not null,
    raster            text,
    max_fail          integer  default 4,
    max_retry         integer  default 3,
    send_nke          boolean  default false,
    app_reset_subcode smallint,
    multi_frames      smallint default 0
);

create table if not exists public.acl_key_access
(
    security_id integer,
    object_id   integer,
    mask        integer,
    displayname text,
    principal   boolean,
    path        text,
    public      boolean,
    key_id      integer
);

create table if not exists public.calculator
(
    calculator_id integer generated by default as identity primary key,
    asset_id      integer not null,
    subtype       text    not null,
    attribute     text    not null,
    formula       text,
    unit          text,
    virtual       boolean default false,
    filter        json,
    offset_mode   text default '' not null,
    "offset"      numeric,
    unique (asset_id, subtype, attribute)
);

insert into public.acl_key_access (security_id, object_id, mask, displayname, principal, path, public, key_id)
values  (null, null, 3, null, false, 'api.nodes', false, 1),
        (null, null, 3, null, false, 'api.agents', false, 1),
        (null, null, 3, null, false, 'api.agent.devices', false, 1),
        (null, null, 3, null, false, 'api.agent.devices.mappings', false, 1),
        (null, null, 3, null, false, 'api.alarms', false, 1),
        (null, null, 3, null, false, 'api.alarms.history', false, 1),
        (null, null, 3, null, false, 'api.alarms.highest', false, 1),
        (null, null, 3, null, false, 'api.alarm.rules', false, 1),
        (null, null, 3, null, false, 'api.alarm.listener', false, 1),
        (null, null, 3, null, false, 'api.apps', false, 1),
        (null, null, 3, null, false, 'api.apps.patches', false, 1),
        (null, null, 3, null, false, 'api.asset.types', false, 1),
        (null, null, 3, null, false, 'api.asset.types.attributes', false, 1),
        (null, null, 3, null, false, 'api.assets', false, 1),
        (null, null, 3, null, false, 'api.bulk.assets', false, 1),
        (null, null, 3, null, false, 'api.aggregations', false, 1),
        (null, null, 3, null, false, 'api.data.trends', false, 1),
        (null, null, 3, null, false, 'api.data.listener', false, 1),
        (null, null, 3, null, false, 'api.data.aggregated', false, 1),
        (null, null, 3, null, false, 'api.data', false, 1),
        (null, null, 3, null, false, 'api.bulk.data', false, 1),
        (null, null, 3, null, false, 'api.widget.types', false, 1),
        (null, null, 3, null, false, 'api.dashboards', false, 1),
        (null, null, 3, null, false, 'api.dashboards.widgets', false, 1),
        (null, null, 3, null, false, 'api.message.receipts', false, 1),
        (null, null, 3, null, false, 'api.send.mail', false, 1),
        (null, null, 3, null, false, 'api.send.notification', false, 1),
        (null, null, 3, null, false, 'api.qr.codes', false, 1),
        (null, null, 3, null, false, 'api.users', false, 1),
        (null, null, 3, null, false, 'api.projects', false, 1),
        (null, null, 3, null, false, 'api.tags', false, 1),
        (null, null, 3, null, false, 'api.asset.listener', false, 1),
        (null, null, 3, null, false, 'attribute.display', false, 1),
        (null, null, 3, null, false, 'api.calculation.rules', false, 1);

create table if not exists public.keyauth (
    key_id  integer,
    key     text,
    expires double precision
);

insert into public.keyauth (key_id, key, expires)
values  (1, 'secret', null);

create table if not exists public.dashboard (
    dashboard_id serial unique,
    user_id      text     not null,
    proj_id      text     not null,
    name         text,
    seq          smallint default 0,
    primary key (user_id, proj_id, dashboard_id)
    );

create table if not exists public.eliona_secret
(
    schema text not null primary key,
    secret text
);

create sequence if not exists public.eliona_user_user_id_seq;

create table if not exists public.eliona_user
(
    user_id      text                     default (nextval('eliona_user_user_id_seq'::regclass))::text not null primary key,
    firstname    text,
    lastname     text,
    language     text            default 'en'::text,
    tags         text[],
    validity     interval                 default '08:00:00'::interval,
    email        text                                                                            not null,
    password     text,
    hidden       boolean                  default false                                                not null,
    schema       text                     default 'api'::text                                          not null,
    phone        text,
    mobile       text,
    pager        text,
    mail2service json,
    slack        text,
    google_chat  text,
    created_at   timestamp with time zone default now()                                                not null,
    modified_at  timestamp with time zone default now()                                                not null,
    last_login   timestamp with time zone,
    archived     boolean                  default false                                                not null,
    created_by   text,
    modified_by  text,
    role_id      integer                  default 2                                                    not null,
    deleted_by   text,
    deleted_at   timestamp with time zone,
    timezone text
);

create unique index if not exists eliona_user_lower_email
    on public.eliona_user (lower(email::text));

create sequence if not exists public.eliona_project_proj_id_seq;

create table if not exists public.eliona_project (
    proj_id     text    default (nextval('eliona_project_proj_id_seq'::regclass))::text not null primary key,
    displayname text,
    location    text,
    email       text,
    regexp      text,
    names       text[],
    icon        text,
    logo        text,
    palette     json,
    logo_big    boolean default false,
    logo_white  boolean default false,
    unique (proj_id, displayname)
);

create table if not exists public.tags (
    name        text                 not null unique,
    color_id    integer default 3    not null,
    custom      boolean default true not null,
    category_id integer,
    tag_id      integer generated by default as identity primary key
);

create table if not exists public.gui_access (
    id        integer generated by default as identity        primary key,
    asset_id  integer not null,
    subtype   text    not null,
    attribute text    not null,
    unit      text,
    precision smallint,
    min       numeric,
    max       numeric,
    step      numeric,
    map       json,
    viewer    boolean,
    ar        boolean,
    seq       smallint,
    unique (asset_id, subtype, attribute)
);

create table if not exists public.user_notification (
    id          bigserial        primary key,
    ts          timestamp with time zone default now() not null,
    user_id     text                                   not null,
    author_id   text                     ,
    proj_id     text,
    alarm_id    integer,
    ticket_id   bigint,
    translation json,
    data        json,
    seen        boolean                  default false not null,
    read        boolean                  default false not null,
    deleted     boolean                  default false not null,
    reminder_at timestamp with time zone,
    summarized  boolean default false not null,
    detail text,
    link text
);

insert into public.eliona_secret (schema, secret)
values  ('api', 'secret');

create table if not exists public.eliona_config
(
    cust_id          text        unique,
    owner_id         text,
    displayname      text,
    domain_name      text,
    retention_time   integer                  default 24,
    version          text,
    latest_version   text,
    secret           text,
    iv_project       numeric                  default 100,
    iv_attribute     numeric                  default 5,
    iv_operator      numeric                  default 5,
    iv_engin         numeric                  default 25,
    iv_admin         numeric                  default 50,
    iv_superadmin    numeric                  default 75,
    iv_edge_node     numeric                  default 100,
    iv_rule          numeric                  default 1,
    modified_by      text                     ,
    modified_at      timestamp with time zone default now() not null,
    logfile_lifespan integer                  default 1
);

INSERT INTO public.eliona_config (cust_id, owner_id, displayname, domain_name, retention_time, version,
                                  latest_version, iv_project, iv_attribute, iv_operator, iv_engin, iv_admin,
                                  iv_superadmin, iv_edge_node, iv_rule, modified_by, modified_at,
                                  logfile_lifespan) VALUES
                                                        ('90', '90', 'Test customer',
                                                         'test.eliona.io', 3, 'v10.1.0',
                                                         'v10.0.4', 100, 5, 5, 25, 50, 75, 100, 1,
                                                         null, '2023-05-31 11:44:44.158240 +00:00', 1);

create schema if not exists import;

create table if not exists import.asset
(
    id           bigint generated by default as identity primary key,
    batch_id     integer                  default 0                          not null,
    resource_id  text                                                        not null unique,
    asset_id     integer
                                                                             references public.asset
                                                                                 on update cascade on delete set null,
    proj_id      text,
    gai          text                                                        not null,
    name         text,
    asset_type   text,
    lat          double precision,
    lon          double precision,
    storey       smallint,
    description  text,
    tags         text[],
    ar           boolean                  default false                      not null,
    urldoc       json,
    created_by   text,
    created_at   timestamp with time zone default now()                      not null,
    modified_by  text,
    modified_at  timestamp with time zone default now()                      not null,
    deleted_by   text,
    deleted_at   timestamp with time zone,
    modified_cnt bigint                   default 1                          not null,
    imported_by  text,
    imported_at  timestamp with time zone,
    imported     boolean generated always as ((asset_id IS NOT NULL)) stored not null,
    uin          text[],
    loc_path  ltree unique,
    func_path ltree unique,
    modified_by_api boolean default false NOT NULL,
    tracker_id   integer,
    key_access  boolean
);
