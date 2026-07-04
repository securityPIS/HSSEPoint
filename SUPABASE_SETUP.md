# HSSE POINT — Setup Cloud & Login (Supabase + Google)

Aplikasi mendukung **dua mode**:

- **Mode Lokal** (default bila belum dikonfigurasi): data denah & titik disimpan di browser (IndexedDB), tanpa login. Persis seperti versi sebelumnya.
- **Mode Cloud**: login Google, 3 role (User / Management / Admin), data tersimpan di Supabase dan difilter **per perusahaan**, bisa diakses lintas perangkat & dibagi tim.

Ikuti langkah di bawah untuk mengaktifkan Mode Cloud.

---

## 1. Buat / buka project Supabase
Di [supabase.com](https://supabase.com) buat project. Catat dari **Project Settings → API**:
- **Project URL** — mis. `https://abcдефgh.supabase.co`
- **anon public key** — kunci `anon` (AMAN ditaruh di client, dilindungi RLS). **Jangan** pakai `service_role`.

## 2. Jalankan skrip database
Buka **SQL Editor → New query**, tempel seluruh isi [`supabase/setup.sql`](supabase/setup.sql), lalu **Run**.
Ini membuat tabel `profiles`, `companies`, `user_companies`, `locations`, beserta trigger, RPC, dan seluruh kebijakan **Row Level Security**.

## 3. Aktifkan Login Google
1. **Google Cloud Console** → buat *OAuth 2.0 Client ID* (tipe *Web application*).
   - **Authorized redirect URI**: `https://<PROJECT-REF>.supabase.co/auth/v1/callback`
   - Salin **Client ID** & **Client Secret**.
2. **Supabase → Authentication → Providers → Google**: aktifkan, tempel Client ID & Secret, simpan.
3. **Supabase → Authentication → URL Configuration → Redirect URLs**: tambahkan URL tempat aplikasi di-host, contoh:
   - `https://securitypis.github.io/HSSEPoint/` (GitHub Pages), atau
   - `http://localhost:8000/` saat uji lokal.
   > Login Google butuh origin **http/https** yang valid — membuka file `index.html` langsung (`file://`) tidak akan bekerja untuk OAuth. Host lewat GitHub Pages atau server statis apa pun.

## 4. Isi kredensial di aplikasi
Buka `index.html`, cari `SUPABASE_CONFIG`, isi:

```js
const SUPABASE_CONFIG = {
    url: 'https://<PROJECT-REF>.supabase.co',
    anonKey: '<ANON-PUBLIC-KEY>'
};
```

Muat ulang halaman → layar **Login** muncul.

## 5. Jadikan diri Anda Admin pertama
1. Login sekali via Google (profil Anda otomatis terbuat dengan status *new*).
2. Di **SQL Editor**, jalankan (ganti email Anda):
   ```sql
   update public.profiles set role = 'admin', status = 'active'
   where email = 'EMAIL-ANDA@gmail.com';
   ```
3. Muat ulang aplikasi → Anda masuk sebagai **Admin**, tombol **Kelola User** muncul di header.

---

## Alur pengguna baru
1. Klik **Masuk dengan Google**.
2. Isi **Nama Lengkap, No. Telepon, Divisi** → **Request Access**.
3. Status menjadi *pending* → layar **Menunggu Persetujuan**.
4. **Admin** membuka **Kelola User → Pengguna**, menekan **Setujui & Simpan**, memilih **role** dan mencentang **perusahaan** (boleh lebih dari satu).
5. Pengguna menekan **Periksa Status** (atau login ulang) → masuk aplikasi.

## Role & hak akses
| Role | Hak |
|------|-----|
| **user** | Tambah / ubah / hapus lokasi & titik pada perusahaan yang ditugaskan |
| **management** | Hanya baca (semua kontrol edit disembunyikan/dinonaktifkan) |
| **admin** | Semua hak + **Kelola User**: setujui/tolak user, atur role, tetapkan perusahaan, kelola daftar perusahaan |

Data lokasi difilter otomatis: setiap user hanya melihat perusahaan yang ditugaskan kepadanya (admin melihat semua). Penegakan dilakukan di server lewat **RLS** — bukan sekadar di UI.

## Catatan teknis
- Gambar denah & foto disimpan sebagai data URL (base64) di dalam kolom `jsonb` `locations.data`. Untuk denah sangat besar, pertimbangkan memindahkannya ke **Supabase Storage** di iterasi berikutnya.
- Selama `SUPABASE_CONFIG` masih placeholder, aplikasi tetap berjalan **Mode Lokal** sehingga tidak ada yang rusak sebelum konfigurasi selesai.
