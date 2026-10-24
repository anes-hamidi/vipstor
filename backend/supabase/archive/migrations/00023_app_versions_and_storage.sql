-- ==============================================================================
-- 00023_app_versions_and_storage.sql
-- Private Over-The-Air (OTA) Application Update System
-- Manages in-house releases across Android, iOS, and Windows
-- ==============================================================================

-- 1. App Versions Table
create table if not exists public.app_versions (
    id uuid primary key default gen_random_uuid(),
    app_type text not null check (app_type in ('staff_app', 'customer_app')),
    platform text not null check (platform in ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    version_name text not null,                   -- e.g. '1.1.0'
    build_number integer not null,                -- e.g. 15
    min_supported_build integer not null default 1, -- Forces update if current_build < min_supported_build
    download_url text not null,                   -- Direct download link (APK, MSIX, EXE, ZIP)
    manifest_url text,                            -- iOS itms-services manifest.plist URL
    release_notes text,                           -- Markdown / Arabic release notes
    is_mandatory boolean not null default false,  -- If true, blocks usage until updated
    file_size_bytes bigint,                       -- File size in bytes for download progress estimation
    published_by uuid references auth.users(id),
    published_at timestamptz not null default now(),
    created_at timestamptz not null default now()
);

-- Index for instant lookup of latest version per app & platform
create index if not exists idx_app_versions_lookup 
    on public.app_versions (app_type, platform, build_number desc);

-- 2. Row Level Security (RLS)
alter table public.app_versions enable row level security;

-- Everyone (anon and authenticated) can query app versions to check for updates
drop policy if exists "Allow public read access to app_versions" on public.app_versions;
create policy "Allow public read access to app_versions"
    on public.app_versions for select
    using (true);

-- Only moderators or service_role can insert/update app_versions
drop policy if exists "Allow moderators to manage app_versions" on public.app_versions;
create policy "Allow moderators to manage app_versions"
    on public.app_versions for all
    using (
        exists (
            select 1 from public.users u
            where u.id = auth.uid()
            and u.role = 'moderator'
        )
    )
    with check (
        exists (
            select 1 from public.users u
            where u.id = auth.uid()
            and u.role = 'moderator'
        )
    );

-- 3. Storage Bucket for App Releases
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'app-releases',
    'app-releases',
    true,
    524288000, -- 500 MB max per installer
    array[
        'application/vnd.android.package-archive',
        'application/octet-stream',
        'application/x-msdos-program',
        'application/x-msi',
        'application/zip',
        'text/xml',
        'application/xml',
        'text/plain'
    ]
)
on conflict (id) do update set
    public = true,
    file_size_limit = 524288000;

-- Storage Policies for 'app-releases'
drop policy if exists "Public Access for App Releases" on storage.objects;
create policy "Public Access for App Releases"
    on storage.objects for select
    using (bucket_id = 'app-releases');

drop policy if exists "Moderator and Service Upload for App Releases" on storage.objects;
create policy "Moderator and Service Upload for App Releases"
    on storage.objects for insert
    with check (
        bucket_id = 'app-releases' and (
            auth.role() = 'service_role' or
            exists (
                select 1 from public.users u
                where u.id = auth.uid()
                and u.role = 'moderator'
            )
        )
    );

-- 4. RPC Function to get latest version cleanly
create or replace function public.rpc_get_latest_app_version(
    p_app_type text,
    p_platform text
)
returns table (
    id uuid,
    app_type text,
    platform text,
    version_name text,
    build_number integer,
    min_supported_build integer,
    download_url text,
    manifest_url text,
    release_notes text,
    is_mandatory boolean,
    file_size_bytes bigint,
    published_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
    select 
        id,
        app_type,
        platform,
        version_name,
        build_number,
        min_supported_build,
        download_url,
        manifest_url,
        release_notes,
        is_mandatory,
        file_size_bytes,
        published_at
    from public.app_versions
    where app_type = p_app_type
      and platform = p_platform
    order by build_number desc
    limit 1;
$$;

grant execute on function public.rpc_get_latest_app_version(text, text) to anon, authenticated, service_role;

-- 5. Seed initial placeholder release for testing
insert into public.app_versions (
    app_type,
    platform,
    version_name,
    build_number,
    min_supported_build,
    download_url,
    manifest_url,
    release_notes,
    is_mandatory
)
values 
(
    'staff_app',
    'android',
    '1.0.1',
    2,
    1,
    'https://raw.githubusercontent.com/vipsmock/releases/main/staff_app_v1.0.1.apk',
    null,
    '• إضافة ميزة تسوية عهدة السائقين النقدية في نهاية الوردية' || chr(10) ||
    '• تحسين طباعة إيصالات نقاط البيع والتقارير اليومية Z-Report' || chr(10) ||
    '• إصلاحات عامة في مزامنة الرصيد والأداء دون اتصال',
    false
),
(
    'staff_app',
    'windows',
    '1.0.1',
    2,
    1,
    'https://raw.githubusercontent.com/vipsmock/releases/main/staff_app_windows_v1.0.1.zip',
    null,
    '• إضافة ميزة تسوية عهدة السائقين النقدية في نهاية الوردية' || chr(10) ||
    '• دعم شاشات نقاط البيع الكبيرة والطباعة الحرارية المباشرة',
    false
)
on conflict do nothing;
