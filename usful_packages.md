# Free Packages for a Supabase Wholesale Shop App

Only free, open-source packages (MIT / BSD / Apache). No Firebase, no Syncfusion, no OneSignal, no Google Maps billing, no paid sync services.
Supabase itself: use the free plan (check current limits) or self-host it for free.

---

## 1. Supabase and Data

| Package | Use |
|---|---|
| `supabase_flutter` | Auth, Postgres, Realtime, Storage, Edge Functions |
| `drift` + `drift_dev` + `sqlite3_flutter_libs` | Local offline database and sync queue |
| `brick_offline_first_with_supabase` (+ `brick_*` generators) | Optional open-source offline-first layer for Supabase |
| `path_provider`, `path` | File locations |
| `shared_preferences` | Small settings (selected printer, language) |
| `flutter_secure_storage` | PIN hash, device token |
| `uuid` | Client-generated IDs for offline records |
| `decimal` or `money2` | Accurate money math |
| `connectivity_plus` | Offline/online detection |
| `workmanager` | Background sync jobs (Android/iOS) |
| `rxdart` | Combine realtime streams |
| `collection` | Grouping and aggregation |
| `intl` | Currency, dates, number formats |

## 2. Architecture and Models

| Package | Use |
|---|---|
| `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` | State management (wrap Supabase streams) |
| `go_router` | Routing with role-based guards |
| `freezed`, `freezed_annotation` | Immutable models |
| `json_serializable`, `json_annotation` | Map Supabase rows to models |
| `build_runner` | Code generation |
| `equatable` | Value equality |
| `get_it` (optional) | Service locator |

## 3. Auth and Security

| Package | Use |
|---|---|
| `local_auth` | Fingerprint / face unlock |
| `pinput` | Cashier PIN input |
| `crypto` | Hashing, audit log hash chain |
| `encrypt` | Encrypt local sensitive data |
| `permission_handler` | Camera, Bluetooth, location permissions |
| `device_info_plus`, `package_info_plus` | Record which terminal did an action (audit log) |
| `network_info_plus` | Local IP / WiFi info |

## 4. Design and UI

| Package | Use |
|---|---|
| `flex_color_scheme` | Material 3 themes, dark mode |
| `google_fonts` | Fonts (bundle the font files for offline use) |
| `flutter_svg` | SVG icons |
| `lucide_icons_flutter` / `font_awesome_flutter` / `iconsax_flutter` | Icon sets |
| `responsive_framework` or `flutter_screenutil` | Phone, tablet, desktop layouts |
| `flutter_adaptive_scaffold` | Adaptive navigation (rail/drawer/bottom bar) |
| `data_table_2` | Tables for products, orders, audit log |
| `pluto_grid` | Excel-like grid for admin screens |
| `flutter_staggered_grid_view` | POS product grid |
| `infinite_scroll_pagination` | Paged lists with Supabase `range()` |
| `flutter_form_builder`, `form_builder_validators` | Complex forms |
| `dropdown_search` | Customer / supplier / product pickers |
| `flutter_typeahead` | Fast search suggestions |
| `flutter_slidable` | Swipe actions |
| `cached_network_image` | Product images from Supabase Storage |
| `shimmer` / `skeletonizer` | Loading placeholders |
| `flutter_animate`, `lottie` | Animations |
| `toastification` | In-app notifications and toasts |
| `gap` | Spacing |
| `timeline_tile` | Order / delivery status timeline |
| `percent_indicator` | KPI progress |
| `flutter_localizations` + `intl` (built in), `easy_localization` | Arabic / French / English, RTL |

## 5. Analytics and Reports (business analytics, free)

| Package | Use |
|---|---|
| `fl_chart` | Line, bar, pie charts |
| `graphic` | Advanced charts |
| `pie_chart` | Simple pie charts |
| `flutter_heatmap_calendar` | Sales heatmap |
| `data_table_2`, `pluto_grid` | Report tables |
| `excel` | Export reports to .xlsx |
| `csv` | Import/export CSV |

Compute totals in Supabase using SQL views and RPC functions, then chart the result.

## 6. Barcode and QR

| Package | Use |
|---|---|
| `mobile_scanner` | Camera barcode/QR scanning |
| `flutter_zxing` | Alternative scanner (also desktop) |
| `barcode_widget` | Show/generate barcodes |
| `barcode` | Barcodes inside PDFs |
| `qr_flutter` | QR codes (invoice, delivery confirmation) |
| Built-in `KeyboardListener` / `TextField` + `FocusNode` | USB / Bluetooth hardware scanners (they act as keyboards) |

## 7. Invoices and Printing (LAN / WiFi / Bluetooth / USB)

| Package | Use |
|---|---|
| `pdf` | Create invoices, delivery notes, purchase orders, labels |
| `printing` | Print / preview / share PDFs |
| `esc_pos_utils_plus` | Build ESC/POS receipt commands |
| Built-in `dart:io` `Socket` (port 9100) | LAN / WiFi thermal printers |
| `flutter_thermal_printer` | USB, BLE and network thermal printers |
| `print_bluetooth_thermal` | Classic Bluetooth printers (Android) |
| `flutter_blue_plus` | BLE printers and devices |
| `flutter_libserialport` / `usb_serial` | USB / serial printers, scales, cash drawer |
| `screenshot` + `image` | Render Arabic receipts as an image for thermal printers |
| `number_to_words` | Amount in words |
| `share_plus` | Share invoice (WhatsApp, email, etc.) |
| `open_filex` | Open generated files |
| `url_launcher` | Call, WhatsApp, open maps |
| `mailer` | Send invoice by SMTP email (use your own free mail account) |

## 8. Delivery Driver (no paid map service)

| Package | Use |
|---|---|
| `geolocator` | GPS location |
| `geocoding` | Address to coordinates |
| `flutter_map` + `latlong2` | Free OpenStreetMap maps (read the tile usage policy; for heavy use choose a free-tier tile provider or host tiles) |
| `flutter_background_service` | Tracking and Realtime connection while in background (Android) |
| `wakelock_plus` | Keep screen on during delivery |
| `signature` | Proof-of-delivery signature |
| `image_picker`, `flutter_image_compress` | Delivery photos |
| `battery_plus` | Driver device battery |

Navigation: open the driver's installed Maps/Waze app with `url_launcher` or `maps_launcher` (free, no API key).

## 9. Notifications (no Firebase)

| Package | Use |
|---|---|
| `flutter_local_notifications` | Local notifications triggered by Supabase Realtime events |
| `flutter_background_service` | Keeps Realtime alive on Android when the app is in the background |
| `unifiedpush` (+ self-hosted ntfy) | Free real push without Google, needs your own server |
| `toastification` | In-app banners |

## 10. Desktop POS (Windows / Linux / macOS)

| Package | Use |
|---|---|
| `window_manager` | Fullscreen / kiosk mode |
| `hotkey_manager` | Keyboard shortcuts for cashiers |
| `launch_at_startup` | Start with the system |
| `tray_manager` | System tray |
| `file_selector` / `file_picker` | File dialogs |
| `desktop_multi_window` | Customer-facing second screen |
| `sqflite_common_ffi` (if using sqflite) | SQLite on desktop |

## 11. Files and Backup

| Package | Use |
|---|---|
| `file_picker` | Import / restore |
| `archive` | Zip backups |
| `image_cropper` | Crop product photos |
| `cross_file` | File abstraction |

## 12. Logging and Error Tracking (free)

| Package | Use |
|---|---|
| `logger` | Developer logging |
| `talker_flutter`, `talker_dio_logger` | In-app log viewer |
| `flutter_dotenv` or `envied` | Keep Supabase URL/anon key out of source (the anon key is public by design, rely on RLS) |

## 13. Dev Tools and Testing

| Package | Use |
|---|---|
| `flutter_lints` / `very_good_analysis` | Lint rules |
| `mocktail` | Mocking |
| `flutter_test`, `integration_test` | Built-in testing |
| `faker` | Test data |
| `alchemist` | Golden tests |
| `flutter_launcher_icons`, `flutter_native_splash` | App icon and splash |
| `flutter_flavorizr` | Dev / production flavors |

## Supabase-Side Free Tools (not Flutter packages)

| Tool | Use |
|---|---|
| Supabase CLI | Local development, migrations, Edge Function deploy |
| Supabase Studio | Table editor, SQL editor, RLS policies |
| Postgres extensions: `pgcrypto`, `pg_cron`, `postgis` | Audit hashes, scheduled jobs, delivery geography |
| Database Webhooks and Edge Functions | Notifications, staff creation, emails |
| Realtime (Postgres Changes, Broadcast, Presence) | Live stock, orders, driver location |
| Storage buckets | Product images, delivery proofs, invoices, backups |

## Left Out on Purpose (cost or lock-in)

`firebase_*`, `onesignal_flutter`, `google_maps_flutter` (billing key), `syncfusion_*` (license terms), `powersync` cloud (paid plans beyond free tier), paid SMS/WhatsApp APIs.

---

## Minimal Free pubspec

```yaml
dependencies:
  supabase_flutter:
  flutter_riverpod:
  riverpod_annotation:
  go_router:
  freezed_annotation:
  json_annotation:
  drift:
  sqlite3_flutter_libs:
  path_provider:
  shared_preferences:
  flutter_secure_storage:
  connectivity_plus:
  workmanager:
  uuid:
  decimal:
  intl:
  collection:
  rxdart:
  local_auth:
  pinput:
  permission_handler:
  device_info_plus:
  package_info_plus:
  mobile_scanner:
  barcode_widget:
  qr_flutter:
  pdf:
  printing:
  esc_pos_utils_plus:
  flutter_thermal_printer:
  flutter_blue_plus:
  screenshot:
  image:
  share_plus:
  url_launcher:
  excel:
  csv:
  file_picker:
  image_picker:
  geolocator:
  flutter_map:
  latlong2:
  flutter_background_service:
  flutter_local_notifications:
  signature:
  wakelock_plus:
  fl_chart:
  data_table_2:
  flex_color_scheme:
  google_fonts:
  flutter_svg:
  cached_network_image:
  flutter_form_builder:
  form_builder_validators:
  infinite_scroll_pagination:
  shimmer:
  toastification:
  talker_flutter:

dev_dependencies:
  build_runner:
  freezed:
  json_serializable:
  riverpod_generator:
  drift_dev:
  mocktail:
  flutter_lints:
```

Note: confirm each package's license and latest version on pub.dev before adding it.