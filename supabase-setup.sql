-- Usmania Stationers & Opticals: Supabase database setup
-- Run this entire file once in Supabase Dashboard > SQL Editor > New query.

create extension if not exists pgcrypto;

-- 1) Admin accounts. Create the user first in Authentication > Users,
-- then insert that user's UUID into this table (instructions below).
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now()
);

create or replace function public.is_shop_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = auth.uid()
  );
$$;

-- 2) Categories
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text not null default '',
  image_url text not null default '',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3) Products. price_text intentionally supports the initial placeholder "0000".
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null,
  description text not null default '',
  image_url text not null default '',
  price_text text not null default '0000',
  price_label text not null default 'PKR',
  show_price boolean not null default true,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists products_category_id_idx on public.products(category_id);
create index if not exists products_active_idx on public.products(is_active);

-- 4) Product options, e.g. Notebook > Single Line / Four Line.
create table if not exists public.product_options (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null,
  price_text text not null default '0000',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(product_id, name)
);

create index if not exists product_options_product_id_idx on public.product_options(product_id);

-- 5) Customer inquiries, including optical prescription details and uploaded file path.
create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  inquiry_type text not null default 'general',
  customer_name text not null,
  phone text not null,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null default '',
  selected_option text not null default '',
  quantity text not null default '1',
  message text not null default '',
  prescription_details text not null default '',
  prescription_file_path text not null default '',
  status text not null default 'new' check (status in ('new','contacted','completed','cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists inquiries_created_at_idx on public.inquiries(created_at desc);
create index if not exists inquiries_status_idx on public.inquiries(status);

-- updated_at maintenance trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists categories_set_updated_at on public.categories;
create trigger categories_set_updated_at before update on public.categories
for each row execute function public.set_updated_at();

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products
for each row execute function public.set_updated_at();

-- Row Level Security
alter table public.admin_users enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_options enable row level security;
alter table public.inquiries enable row level security;

-- Admin users: only an existing admin can view/manage the admin list.
drop policy if exists "Admins can view admin users" on public.admin_users;
create policy "Admins can view admin users" on public.admin_users
for select to authenticated using (public.is_shop_admin());
drop policy if exists "Admins can manage admin users" on public.admin_users;
create policy "Admins can manage admin users" on public.admin_users
for all to authenticated using (public.is_shop_admin()) with check (public.is_shop_admin());

-- Public catalogue reads; only admins can write.
drop policy if exists "Public can read active categories" on public.categories;
create policy "Public can read active categories" on public.categories
for select to anon, authenticated using (is_active or public.is_shop_admin());
drop policy if exists "Admins manage categories" on public.categories;
create policy "Admins manage categories" on public.categories
for all to authenticated using (public.is_shop_admin()) with check (public.is_shop_admin());

drop policy if exists "Public can read active products" on public.products;
create policy "Public can read active products" on public.products
for select to anon, authenticated using (is_active or public.is_shop_admin());
drop policy if exists "Admins manage products" on public.products;
create policy "Admins manage products" on public.products
for all to authenticated using (public.is_shop_admin()) with check (public.is_shop_admin());

drop policy if exists "Public can read active product options" on public.product_options;
create policy "Public can read active product options" on public.product_options
for select to anon, authenticated using (
  is_active or public.is_shop_admin()
);
drop policy if exists "Admins manage product options" on public.product_options;
create policy "Admins manage product options" on public.product_options
for all to authenticated using (public.is_shop_admin()) with check (public.is_shop_admin());

-- Customers may submit inquiries; only admins can read/update/delete them.
drop policy if exists "Anyone can submit inquiry" on public.inquiries;
create policy "Anyone can submit inquiry" on public.inquiries
for insert to anon, authenticated with check (
  length(trim(customer_name)) > 0 and length(trim(phone)) > 0
);
drop policy if exists "Admins can read inquiries" on public.inquiries;
create policy "Admins can read inquiries" on public.inquiries
for select to authenticated using (public.is_shop_admin());
drop policy if exists "Admins can update inquiries" on public.inquiries;
create policy "Admins can update inquiries" on public.inquiries
for update to authenticated using (public.is_shop_admin()) with check (public.is_shop_admin());
drop policy if exists "Admins can delete inquiries" on public.inquiries;
create policy "Admins can delete inquiries" on public.inquiries
for delete to authenticated using (public.is_shop_admin());

-- Storage buckets. Product photos are publicly viewable; uploads/changes are admin-only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Prescription uploads are private. Anonymous customers can upload a file;
-- only admins can list/read/delete it. Keep the generated object path in inquiries.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('prescriptions', 'prescriptions', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists "Public can view product images" on storage.objects;
create policy "Public can view product images" on storage.objects
for select to anon, authenticated using (bucket_id = 'product-images');
drop policy if exists "Admins upload product images" on storage.objects;
create policy "Admins upload product images" on storage.objects
for insert to authenticated with check (bucket_id = 'product-images' and public.is_shop_admin());
drop policy if exists "Admins update product images" on storage.objects;
create policy "Admins update product images" on storage.objects
for update to authenticated using (bucket_id = 'product-images' and public.is_shop_admin())
with check (bucket_id = 'product-images' and public.is_shop_admin());
drop policy if exists "Admins delete product images" on storage.objects;
create policy "Admins delete product images" on storage.objects
for delete to authenticated using (bucket_id = 'product-images' and public.is_shop_admin());

drop policy if exists "Customers can upload prescriptions" on storage.objects;
create policy "Customers can upload prescriptions" on storage.objects
for insert to anon, authenticated with check (bucket_id = 'prescriptions');
drop policy if exists "Admins can view prescriptions" on storage.objects;
create policy "Admins can view prescriptions" on storage.objects
for select to authenticated using (bucket_id = 'prescriptions' and public.is_shop_admin());
drop policy if exists "Admins can delete prescriptions" on storage.objects;
create policy "Admins can delete prescriptions" on storage.objects
for delete to authenticated using (bucket_id = 'prescriptions' and public.is_shop_admin());

-- Seed the 9 main categories. Safe to run again.
insert into public.categories (name, slug, description, sort_order) values
('Stationery','stationery','Notebooks, pens, pencils and everyday stationery',1),
('Calculators','calculators','Scientific, student and desktop calculators',2),
('Office Supplies','office-supplies','Files, folders, paper and office essentials',3),
('School Accessories','school-accessories','School bags, bottles and lunch boxes',4),
('Art & Craft','art-craft','Colours, paints, brushes and craft materials',5),
('Gift Items','gift-items','Gift boxes, greeting cards and gift mugs',6),
('Toys','toys','Teddy bears, remote control cars, blocks and games',7),
('Books','books','Kids, school, college, Islamic books, general books and novels',8),
('Glasses & Lenses','glasses-lenses','Frames, sunglasses, prescription lenses and optical services',9)
on conflict (slug) do update set name = excluded.name, description = excluded.description;

-- NEXT: create an Auth user, then register that UUID as the shop admin.
-- Replace the values below and run separately AFTER creating the user in
-- Supabase Dashboard > Authentication > Users.
-- insert into public.admin_users (user_id, email)
-- values ('PASTE-AUTH-USER-UUID-HERE', 'your-admin-email@example.com');
