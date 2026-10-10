// App UI language: English + Spanish chrome, English-only data.
//
// Boundary rule (see SessionStore lang override): locale changes buttons,
// labels, hints, dialogs, snackbars and validation text. It NEVER changes
// data values: product names, SKUs, barcodes, Odoo categories, prices,
// printed labels, TSV export and audit content stay English. Number and
// currency formats stay en_US style ($4.49) so screen, label and Odoo
// always agree.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../session_store.dart';

enum AppLang { en, es }

class Lang extends ChangeNotifier {
  Lang._();
  static final Lang instance = Lang._();

  AppLang _current = AppLang.en;
  AppLang get current => _current;
  bool get isSpanish => _current == AppLang.es;

  /// Load saved override, else device Spanish -> es, else en.
  /// Time-bounded (same 3s convention as SessionStore): a wedged or
  /// unmocked prefs backend must never stall app boot.
  Future<void> load() async {
    String? saved;
    try {
      saved =
          await SessionStore.loadLang().timeout(const Duration(seconds: 3));
    } catch (_) {
      saved = null;
    }
    if (saved != null) {
      _current = saved == 'es' ? AppLang.es : AppLang.en;
    } else {
      try {
        _current =
            ui.PlatformDispatcher.instance.locale.languageCode == 'es'
                ? AppLang.es
                : AppLang.en;
      } catch (_) {
        _current = AppLang.en;
      }
    }
    notifyListeners();
  }

  Future<void> set(AppLang lang) async {
    if (lang == _current) return;
    _current = lang;
    try {
      await SessionStore.saveLang(lang == AppLang.es ? 'es' : 'en');
    } catch (_) {
      // Persistence is best-effort; the in-memory switch still applies.
    }
    notifyListeners();
  }

  /// Test/seeding hook (no persistence).
  @visibleForTesting
  void setForTest(AppLang lang) {
    _current = lang;
    notifyListeners();
  }

  String t(String key) => _strings[_current]?[key] ?? _en[key] ?? key;

  /// Template with {placeholders}.
  String f(String key, [Map<String, String> params = const {}]) {
    var s = t(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// One/other plural (1 -> one, else other incl. 0; same rule both langs).
  String q(String oneKey, String otherKey, int n) =>
      f(n == 1 ? oneKey : otherKey, {'n': '$n'});

  static const _en = <String, String>{
    // Nav + account
    'nav_inventory': 'Inventory',
    'nav_labels': 'Labels',
    'nav_account': 'Account',
    'account_title': 'Account',
    'account_user': 'User: {user}',
    'account_user_none': 'User: —',
    'account_db': 'DB: odoo',
    'account_signout': 'Sign out',
    'account_note': 'POC build. Online-only. Mistakes: fix in Odoo backend.',
    'account_language': 'Language / Idioma',
    'account_language_note':
        'Changes buttons and instructions. Product names, labels and prices stay in English.',
    'lang_english': 'English',
    'lang_spanish': 'Español',
    // Login
    'login_title': 'Cloud 9 Team',
    'login_username': 'Username',
    'login_password': 'Password',
    'login_signin': 'Sign in',
    'login_switch_tip': 'ES',
    // Home
    'home_title': 'Inventory',
    'home_prompt': 'What are you doing?',
    'home_add': 'Add inventory',
    'home_add_sub': 'New product, incl. expiry date',
    'home_manage': 'Manage inventory',
    'home_manage_sub': 'Find an item, fix its details',
    'home_count': 'Update item count',
    'home_count_sub': 'Scan, set quantity, next',
    // Add inventory
    'add_title': 'Add inventory',
    'add_scan': 'Scan barcode',
    'add_barcode': 'Barcode (or type it)',
    'add_nobarcode': 'No barcode',
    'add_nobarcode_hint': 'No barcode on this item — SKU becomes its ID.',
    'add_sku_required': 'SKU is required when there is no barcode.',
    'add_name': 'Name * (in English)',
    'add_sku': 'SKU',
    'add_cost': 'Cost',
    'add_price': 'Price',
    'add_qty': 'Qty',
    'add_expiry': 'Expiry date (optional)',
    'add_expiry_clear': 'Clear date',
    'add_details': 'Details',
    'add_sellable': 'Sellable in POS',
    'add_purchasable': 'Purchasable',
    'add_stocktracked': 'Stock tracked',
    'add_submit': 'Add to inventory',
    'add_continuous': 'Continuous add',
    'add_continuous_sub': 'Scan the next item right after saving',
    'add_update_instead': 'Update count instead',
    'add_dup_msg': 'Already in inventory: {name} (on-hand: {qty})',
    'add_dup_sub': 'Creating again would duplicate it. Update it instead.',
    'add_err_name': 'Name is required (≥ 2 chars, in English).',
    'add_err_cat': 'Pick a category (still loading — try again).',
    'add_err_nums': 'Enter valid cost, price and qty (≥ 0).',
    'add_err_belowcost': 'Below cost — new items must be priced at or above cost.',
    'add_err_sku_inuse': 'SKU in use by {name}.',
    'add_err_barcode_inuse': 'Barcode already used by {name} — update it instead.',
    'add_ok': 'Added {name} — label queued in Labels.',
    'add_fail': 'Could not add {name}. {detail}',
    'add_print': 'Print label',
    'add_view_labels': 'View labels',
    'add_added_title': 'Added to inventory',
    'add_print_sent': 'Label sent for {name}',
    'add_cats_loading': 'Categories still loading…',
    // Labels tab
    'batch_cancel': 'Cancel',
    'batch_save': 'Save',
    'batch_shared': 'Shared TSV — run gen-label-pngs.js on the PC',
    'batch_view': 'View',
    'batch_done_select': 'Done selecting',
    'batch_browse': 'Browse items',
    'batch_print_all': 'Print all labels',
    'batch_new': 'New collection',
    'batch_rename': 'Rename',
    'batch_duplicate': 'Duplicate',
    'batch_delete': 'Delete collection',
    'batch_clear': 'Clear lines',
    'batch_share': 'Share TSV',
    'batch_collection': 'Collection',
    'batch_empty':
        'Empty.\nScan in Receive with "+ Label" on,\nor browse items to add some.',
    'batch_print_selected': 'Print selected ({n})',
    'batch_sel_one': '{n} selected',
    'batch_sel_other': '{n} selected',
    'batch_printing': 'Printing {name}',
    'batch_job_title': 'Printing',
    'batch_print_selected_title': 'Printing selection',
    // Browse / manage / picker
    'browse_added_n': 'Added {n} to labels',
    'browse_addall_title': 'Add all to labels?',
    'browse_addall_msg': '{n} items × 1 copy will be added.',
    'browse_cancel': 'Cancel',
    'browse_addall': 'Add all',
    'browse_addall_filter': 'Add all in filter',
    'browse_pick_hint':
        'Select items, or add everything matching search + category.',
    'browse_add_n': 'Add ({n})',
    'browse_addprint_n': 'Add & Print ({n})',
    'browse_addall_instead': 'Add all in filter instead',
    'browse_nocode':
        'No barcode/SKU — open Update count and type the name lookup there.',
    'browse_onhand': 'On hand: {qty}',
    'browse_barcode': 'Barcode:',
    'browse_sku': 'SKU:',
    'browse_price': 'Price:',
    'browse_cost': 'Cost:',
    'browse_category': 'Category:',
    'browse_expires': 'Expires:',
    'browse_selected': 'Selected — tap to remove',
    'browse_select_item': 'Select this item',
    'browse_print': 'Print label',
    'browse_label_sent': 'Label sent for {name}',
    'browse_empty': 'Search or scan to find items.',
    'browse_nomatch': 'No match for "{q}".',
    'browse_add_new': 'Add as new item',
    'browse_done_select': 'Done selecting',
    'browse_select_labels': 'Select labels',
    'browse_search_hint': 'Search name, barcode, SKU, or category',
    'browse_scan': 'Scan',
    'browse_category_label': 'Category',
    'browse_all_cats': 'All categories',
    'browse_load_more': 'Load more',
    'browse_add_n_labels': 'Add {n} to labels',
    'browse_details': 'Details',
    'browse_no_code': 'no code',
    'browse_in_collection': 'In collection',
    // Receive / count
    'recv_session': 'Session expired — sign in again (Account tab).',
    'recv_err_costprice': 'Enter valid cost and price (≥ 0).',
    'recv_err_sku': 'SKU in use by {name} — change it or tap Use anyway.',
    'recv_saved': 'Saved {name} +{qty} → {after}',
    'recv_counted': 'Counted {name}: → {after}',
    'recv_storable': '{name} is now Storable — save again.',
    'recv_archived': 'Archived {name}',
    'recv_archive_title': 'Archive product?',
    'recv_archive_msg':
        '{name}\nBarcode: {code}\n\nIt will disappear from POS and scans. You can restore it in Odoo (Archived filter).',
    'recv_archive_btn': 'Archive',
    'recv_cancel': 'Cancel',
    'recv_confirm': 'Confirm',
    'recv_confirm_count': 'Confirm count',
    'recv_updated': 'Updated {name} (no stock change)',
    'recv_prices_updated': 'Prices updated for {name} (no count change)',
    'recv_created': 'Created {name} (0 → {qty})',
    'recv_label_sent': 'Label sent for {name}',
    'recv_reason_title': 'Reason required',
    'recv_reason_label': 'Reason',
    'recv_continue': 'Continue',
    'recv_update_title': 'Update count',
    'recv_receive_title': 'Receive delivery',
    'recv_rapid': 'Rapid scan',
    'recv_scan': 'Scan',
    'recv_barcode_hint': 'Barcode (or type + Go)',
    'recv_go': 'Go',
    'recv_convert_title': 'No stock tracking ({kind})',
    'recv_convert_sub':
        'Odoo cannot hold stock for this type. Convert it to Storable to save quantities here.',
    'recv_convert_btn': 'Convert to Storable',
    'recv_convert_retry': 'Convert to Storable & retry',
    'recv_converting': 'Converting…',
    'recv_dup_title': 'Duplicate barcode — pick the right item',
    'recv_dup_sub':
        'Saving is blocked until you choose. Stock must land on the right variant.',
    'recv_archive_tip': 'Archive {name}',
    'recv_name': 'Name',
    'recv_sku': 'SKU',
    'recv_cost': 'Purchase price (cost)',
    'recv_price': 'Sale price',
    'recv_qty_add': 'Qty to add',
    'recv_qty_count': 'Counted qty',
    'recv_qty_help_receive': 'Leave empty for details only',
    'recv_qty_help_count': 'Leave empty for prices only',
    'recv_reason_req': 'Reason (required)',
    'recv_use_anyway': 'Use anyway',
    'recv_add_label': 'Add to label batch',
    'recv_update': 'Update',
    'recv_setcount': 'Set count',
    'recv_print': 'Print label',
    'recv_archive': 'Archive product',
    'recv_new_title': 'Not in Odoo — new product',
    'recv_new_barcode': 'Barcode: {code}',
    'recv_new_name': 'Name *',
    'recv_create': 'Create & next',
    'recv_adjust_price': 'Adjust price',
    'recv_cats_loading': 'Categories still loading…',
    'recv_maps_to': 'Maps to: {a} + POS {b}',
    'recv_maps_to_fb': 'Maps to: {a} (fallback) + POS {b}',
    'recv_err_name2': 'Name must be at least 2 characters.',
    'recv_err_qty_add':
        'Enter qty to add (≥ 0), or leave empty for details only.',
    'recv_err_count_blank':
        'Enter the counted qty (no default in Count mode).',
    'recv_err_counted': 'Enter counted qty (≥ 0).',
    'recv_err_new_name': 'Name is required (≥ 2 chars).',
    'recv_err_pickcat': 'Pick a category.',
    'recv_err_cats': 'Categories still loading — try again.',
    'recv_err_nums': 'Enter valid cost, price and qty (≥ 0).',
    'recv_err_sku_new': 'SKU in use by {name}.',
    'recv_barcode_inuse':
        'Barcode already used by {name} — opened it instead.',
    'pg_below': 'Below cost — reason required.',
    'pg_delta': 'Large change (>20%) — reason required.',
    // Continuous scan sheet
    'sheet_cam_denied':
        'Camera permission denied — allow it in Settings, or type the barcode below.',
    'sheet_cam_fail':
        'Camera failed to start ({err}). Retry, or type the barcode below.',
    'sheet_retry_cam': 'Retry camera',
    'sheet_not_found': 'Not in Odoo: {code} — create it in single mode.',
    'sheet_dup': 'Duplicate barcode — pick the variant in single mode.',
    'sheet_session': 'Session expired — sign in again.',
    'sheet_unsaved': 'Unsaved edits',
    'sheet_unsaved_msg': '{name} has unconfirmed price/detail edits.',
    'sheet_discard': 'Discard',
    'sheet_edit_single': 'Edit in single mode',
    'sheet_invalid_count':
        'Pending {name} has invalid qty — enter 0 or more.',
    'sheet_invalid_receive':
        'Pending {name} has invalid qty — fix or clear it.',
    'sheet_leave': 'Leave continuous?',
    'sheet_leave_msg': '{name} has an unsaved qty.',
    'sheet_stay': 'Stay',
    'sheet_save_exit': 'Save & exit',
    'sheet_exit': 'Exit',
    'sheet_torch': 'Torch',
    'sheet_type_go': 'Type barcode + Go',
    'sheet_count': 'Count',
    'sheet_receive': 'Receive',
    'sheet_continuous': 'continuous',
    'sheet_counted': 'Counted',
    'sheet_qty': 'Qty',
    'sheet_plus1': '+1',
    'sheet_plus1_save': '+1 save',
    'sheet_save_qty': 'Save qty',
    'sheet_edit_price': 'Edit price/details (single mode)',
    'sheet_price_single': 'Price/detail edits: use single mode',
    'sheet_point': 'Point at a barcode — beep means captured.',
    // Print job
    'job_close': 'Close',
    'job_pause': 'Pause',
    'job_resume': 'Resume',
    'job_cancel': 'Cancel',
    'job_retry_failed': 'Retry failed ({n})',
    'job_retry_selected': 'Retry selected ({n})',
    'job_empty': 'Nothing to print.',
    'job_done': 'Done: {done} printed',
    'job_done_fail': 'Done: {done} printed, {failed} failed',
    'job_paused': 'Paused',
    'job_paused_fail':
        'Paused — {failed} failed (reload paper / check printer)',
    'job_printing': 'Printing… {done}/{total}',
    'job_st_queued': 'queued',
    'job_st_printing': 'printing',
    'job_st_done': 'done',
    'job_st_failed': 'failed',
    'job_st_cancelled': 'cancelled',
    // Scanner + category picker
    'scan_title': 'Scan barcode',
    'scan_torch': 'Torch',
    'scan_retry': 'Retry camera',
    'scan_cam_denied':
        'Camera permission denied — allow it in Settings, or go back and type the barcode.',
    'scan_cam_fail':
        'Camera failed to start ({err}). You can retry, or go back and type the barcode.',
    'scan_point': 'Point at the barcode. Torch is top-right.',
    'cat_choose': 'Tap to choose',
    'cat_label': 'Category *',
    'cat_search': 'Search categories',
    'cat_empty': 'No matches — try another word.',
    'cat_suggested': 'Suggested',
    // Label detail sheet
    'sheet_size': 'Size (e.g. 12 oz, 1 pk)',
    'sheet_size_val': 'Size: {size}',
    'sheet_promo_on': 'Promo ON (Type 02)',
    'sheet_promo': 'Promo (Type 02)',
    'sheet_was': 'Was price *',
    'sheet_ends': 'Ends (e.g. SUN 11/03)',
    'sheet_save': 'Save chip (e.g. SAVE \$1.50)',
    'sheet_apply': 'Apply promo',
    'sheet_remove': 'Remove',
    // Toasts (shared)
    'toast_ok': 'Saved.',
    'toast_fail': 'Failed. {detail}',
    'toast_offline': 'Offline — check connection and retry.',
    'toast_session': 'Session expired — sign in again (Account tab).',
  };

  static const _es = <String, String>{
    'nav_inventory': 'Inventario',
    'nav_labels': 'Etiquetas',
    'nav_account': 'Cuenta',
    'account_title': 'Cuenta',
    'account_user': 'Usuario: {user}',
    'account_user_none': 'Usuario: —',
    'account_db': 'BD: odoo',
    'account_signout': 'Cerrar sesión',
    'account_note':
        'Versión de prueba. Solo en línea. Errores: corríjalos en Odoo.',
    'account_language': 'Language / Idioma',
    'account_language_note':
        'Cambia botones e instrucciones. Nombres, etiquetas y precios siguen en inglés.',
    'lang_english': 'English',
    'lang_spanish': 'Español',
    'login_title': 'Cloud 9 Team',
    'login_username': 'Usuario',
    'login_password': 'Contraseña',
    'login_signin': 'Iniciar sesión',
    'login_switch_tip': 'EN',
    'home_title': 'Inventario',
    'home_prompt': '¿Qué vas a hacer?',
    'home_add': 'Agregar inventario',
    'home_add_sub': 'Producto nuevo, incl. vencimiento',
    'home_manage': 'Gestionar inventario',
    'home_manage_sub': 'Busca un artículo y corrige sus datos',
    'home_count': 'Actualizar conteo',
    'home_count_sub': 'Escanea, ajusta cantidad, sigue',
    'add_title': 'Agregar inventario',
    'add_scan': 'Escanear código',
    'add_barcode': 'Código de barras (o escríbelo)',
    'add_nobarcode': 'Sin código',
    'add_nobarcode_hint': 'Sin código en este artículo — el SKU será su ID.',
    'add_sku_required': 'El SKU es obligatorio sin código de barras.',
    'add_name': 'Nombre * (en inglés)',
    'add_sku': 'SKU',
    'add_cost': 'Costo',
    'add_price': 'Precio',
    'add_qty': 'Cant.',
    'add_expiry': 'Vencimiento (opcional)',
    'add_expiry_clear': 'Borrar fecha',
    'add_details': 'Detalles',
    'add_sellable': 'A la venta en POS',
    'add_purchasable': 'Comprable',
    'add_stocktracked': 'Con inventario',
    'add_submit': 'Agregar al inventario',
    'add_continuous': 'Agregado continuo',
    'add_continuous_sub': 'Escanea el siguiente justo después de guardar',
    'add_update_instead': 'Actualizar conteo mejor',
    'add_dup_msg': 'Ya en inventario: {name} (existencia: {qty})',
    'add_dup_sub': 'Crearlo duplicaría. Mejor actualízalo.',
    'add_err_name': 'El nombre es obligatorio (≥ 2 letras, en inglés).',
    'add_err_cat': 'Elige una categoría (cargando — reintenta).',
    'add_err_nums': 'Costo, precio y cantidad válidos (≥ 0).',
    'add_err_belowcost':
        'Bajo costo — el precio debe ser mayor o igual al costo.',
    'add_err_sku_inuse': 'SKU en uso por {name}.',
    'add_err_barcode_inuse':
        'Código en uso por {name} — mejor actualízalo.',
    'add_ok': '{name} agregado — etiqueta en Etiquetas.',
    'add_fail': 'No se pudo agregar {name}. {detail}',
    'add_print': 'Imprimir etiqueta',
    'add_view_labels': 'Ver etiquetas',
    'add_added_title': 'Agregado al inventario',
    'add_print_sent': 'Etiqueta enviada para {name}',
    'add_cats_loading': 'Cargando categorías…',
    'batch_cancel': 'Cancelar',
    'batch_save': 'Guardar',
    'batch_shared': 'TSV compartido — ejecuta gen-label-pngs.js en la PC',
    'batch_view': 'Ver',
    'batch_done_select': 'Terminar selección',
    'batch_browse': 'Buscar artículos',
    'batch_print_all': 'Imprimir todas',
    'batch_new': 'Nueva colección',
    'batch_rename': 'Renombrar',
    'batch_duplicate': 'Duplicar',
    'batch_delete': 'Borrar colección',
    'batch_clear': 'Vaciar líneas',
    'batch_share': 'Compartir TSV',
    'batch_collection': 'Colección',
    'batch_empty':
        'Vacío.\nEscanea en Recibir con "+ Etiqueta",\no busca artículos para agregar.',
    'batch_print_selected': 'Imprimir selección ({n})',
    'batch_sel_one': '{n} seleccionado',
    'batch_sel_other': '{n} seleccionados',
    'batch_printing': 'Imprimiendo {name}',
    'batch_job_title': 'Imprimiendo',
    'batch_print_selected_title': 'Imprimiendo selección',
    'browse_added_n': '{n} agregados a etiquetas',
    'browse_addall_title': '¿Agregar todo a etiquetas?',
    'browse_addall_msg': '{n} artículos × 1 copia se agregarán.',
    'browse_cancel': 'Cancelar',
    'browse_addall': 'Agregar todo',
    'browse_addall_filter': 'Agregar todo el filtro',
    'browse_pick_hint':
        'Elige artículos o agrega todo lo que coincida con buscar + categoría.',
    'browse_add_n': 'Agregar ({n})',
    'browse_addprint_n': 'Agregar e imprimir ({n})',
    'browse_addall_instead': 'Mejor agregar todo el filtro',
    'browse_nocode':
        'Sin código/SKU — abre Actualizar conteo y busca por nombre.',
    'browse_onhand': 'Existencia: {qty}',
    'browse_barcode': 'Código:',
    'browse_sku': 'SKU:',
    'browse_price': 'Precio:',
    'browse_cost': 'Costo:',
    'browse_category': 'Categoría:',
    'browse_expires': 'Vence:',
    'browse_selected': 'Elegido — toca para quitar',
    'browse_select_item': 'Elegir este artículo',
    'browse_print': 'Imprimir etiqueta',
    'browse_label_sent': 'Etiqueta enviada para {name}',
    'browse_empty': 'Busca o escanea para encontrar artículos.',
    'browse_nomatch': 'Sin resultados para "{q}".',
    'browse_add_new': 'Agregar como nuevo',
    'browse_done_select': 'Terminar selección',
    'browse_select_labels': 'Elegir etiquetas',
    'browse_search_hint': 'Busca nombre, código, SKU o categoría',
    'browse_scan': 'Escanear',
    'browse_category_label': 'Categoría',
    'browse_all_cats': 'Todas las categorías',
    'browse_load_more': 'Cargar más',
    'browse_add_n_labels': 'Agregar {n} a etiquetas',
    'browse_details': 'Detalles',
    'browse_no_code': 'sin código',
    'browse_in_collection': 'En colección',
    'recv_session': 'Sesión vencida — inicia sesión (pestaña Cuenta).',
    'recv_err_costprice': 'Costo y precio válidos (≥ 0).',
    'recv_err_sku':
        'SKU en uso por {name} — cámbialo o toca Usar igual.',
    'recv_saved': '{name} guardado +{qty} → {after}',
    'recv_counted': '{name} contado: → {after}',
    'recv_storable': '{name} ahora es almacenable — guarda de nuevo.',
    'recv_archived': '{name} archivado',
    'recv_archive_title': '¿Archivar producto?',
    'recv_archive_msg':
        '{name}\nCódigo: {code}\n\nDesaparecerá de POS y escaneos. Puedes restaurarlo en Odoo (filtro Archivados).',
    'recv_archive_btn': 'Archivar',
    'recv_cancel': 'Cancelar',
    'recv_confirm': 'Confirmar',
    'recv_confirm_count': 'Confirmar conteo',
    'recv_updated': '{name} actualizado (sin cambio de stock)',
    'recv_prices_updated': '{name} precios (sin cambio de conteo)',
    'recv_created': '{name} creado (0 → {qty})',
    'recv_label_sent': 'Etiqueta enviada para {name}',
    'recv_reason_title': 'Motivo obligatorio',
    'recv_reason_label': 'Motivo',
    'recv_continue': 'Continuar',
    'recv_update_title': 'Actualizar conteo',
    'recv_receive_title': 'Recibir entrega',
    'recv_rapid': 'Escaneo rápido',
    'recv_scan': 'Escanear',
    'recv_barcode_hint': 'Código (o escribe + Ir)',
    'recv_go': 'Ir',
    'recv_convert_title': 'Sin inventario ({kind})',
    'recv_convert_sub':
        'Odoo no guarda existencia para este tipo. Conviértelo a almacenable para guardar aquí.',
    'recv_convert_btn': 'Convertir a almacenable',
    'recv_convert_retry': 'Convertir y reintentar',
    'recv_converting': 'Convirtiendo…',
    'recv_dup_title': 'Código duplicado — elige el correcto',
    'recv_dup_sub':
        'Guardar bloqueado hasta elegir. La existencia debe ir a la variante correcta.',
    'recv_archive_tip': 'Archivar {name}',
    'recv_name': 'Nombre',
    'recv_sku': 'SKU',
    'recv_cost': 'Precio de compra (costo)',
    'recv_price': 'Precio de venta',
    'recv_qty_add': 'Cantidad a agregar',
    'recv_qty_count': 'Cantidad contada',
    'recv_qty_help_receive': 'Vacío = solo detalles',
    'recv_qty_help_count': 'Vacío = solo precios',
    'recv_reason_req': 'Motivo (obligatorio)',
    'recv_use_anyway': 'Usar igual',
    'recv_add_label': 'Agregar a etiquetas',
    'recv_update': 'Actualizar',
    'recv_setcount': 'Fijar conteo',
    'recv_print': 'Imprimir etiqueta',
    'recv_archive': 'Archivar producto',
    'recv_new_title': 'No está en Odoo — producto nuevo',
    'recv_new_barcode': 'Código: {code}',
    'recv_new_name': 'Nombre *',
    'recv_create': 'Crear y sigue',
    'recv_adjust_price': 'Ajustar precio',
    'recv_cats_loading': 'Cargando categorías…',
    'recv_maps_to': 'Mapea a: {a} + POS {b}',
    'recv_maps_to_fb': 'Mapea a: {a} (respaldo) + POS {b}',
    'recv_err_name2': 'El nombre mínimo 2 letras.',
    'recv_err_qty_add':
        'Cantidad a agregar (≥ 0), o vacío para solo detalles.',
    'recv_err_count_blank':
        'Escribe la cantidad contada (sin valor previo en conteo).',
    'recv_err_counted': 'Cantidad contada (≥ 0).',
    'recv_err_new_name': 'El nombre es obligatorio (≥ 2 letras).',
    'recv_err_pickcat': 'Elige una categoría.',
    'recv_err_cats': 'Categorías cargando — reintenta.',
    'recv_err_nums': 'Costo, precio y cantidad válidos (≥ 0).',
    'recv_err_sku_new': 'SKU en uso por {name}.',
    'recv_barcode_inuse':
        'Código en uso por {name} — se abrió mejor.',
    'pg_below': 'Bajo costo — motivo obligatorio.',
    'pg_delta': 'Cambio grande (>20%) — motivo obligatorio.',
    'sheet_cam_denied':
        'Cámara denegada — permite en Ajustes o escribe el código abajo.',
    'sheet_cam_fail':
        'No arrancó la cámara ({err}). Reintenta o escribe el código abajo.',
    'sheet_retry_cam': 'Reintentar cámara',
    'sheet_not_found': 'No está en Odoo: {code} — créalo en modo simple.',
    'sheet_dup': 'Código duplicado — elige la variante en modo simple.',
    'sheet_session': 'Sesión vencida — inicia sesión.',
    'sheet_unsaved': 'Cambios sin guardar',
    'sheet_unsaved_msg': '{name} tiene cambios sin confirmar.',
    'sheet_discard': 'Descartar',
    'sheet_edit_single': 'Editar en modo simple',
    'sheet_invalid_count':
        '{name} pendiente con cantidad inválida — escribe 0 o más.',
    'sheet_invalid_receive':
        '{name} pendiente con cantidad inválida — corrígela o bórrala.',
    'sheet_leave': '¿Salir del continuo?',
    'sheet_leave_msg': '{name} tiene cantidad sin guardar.',
    'sheet_stay': 'Quedarme',
    'sheet_save_exit': 'Guardar y salir',
    'sheet_exit': 'Salir',
    'sheet_torch': 'Linterna',
    'sheet_type_go': 'Escribe código + Ir',
    'sheet_count': 'Conteo',
    'sheet_receive': 'Recibir',
    'sheet_continuous': 'continuo',
    'sheet_counted': 'Contado',
    'sheet_qty': 'Cant.',
    'sheet_plus1': '+1',
    'sheet_plus1_save': '+1 guarda',
    'sheet_save_qty': 'Guardar cant.',
    'sheet_edit_price': 'Editar precio/detalles (modo simple)',
    'sheet_price_single': 'Precio/detalles: usa modo simple',
    'sheet_point': 'Apunta al código — el bip confirma.',
    'job_close': 'Cerrar',
    'job_pause': 'Pausar',
    'job_resume': 'Reanudar',
    'job_cancel': 'Cancelar',
    'job_retry_failed': 'Reintentar fallidos ({n})',
    'job_retry_selected': 'Reintentar elegidos ({n})',
    'job_empty': 'Nada que imprimir.',
    'job_done': 'Listo: {done} impresas',
    'job_done_fail': 'Listo: {done} impresas, {failed} fallidas',
    'job_paused': 'Pausado',
    'job_paused_fail':
        'Pausado — {failed} fallidas (recarga papel / revisa impresora)',
    'job_printing': 'Imprimiendo… {done}/{total}',
    'job_st_queued': 'en cola',
    'job_st_printing': 'imprimiendo',
    'job_st_done': 'lista',
    'job_st_failed': 'fallida',
    'job_st_cancelled': 'cancelada',
    'scan_title': 'Escanear código',
    'scan_torch': 'Linterna',
    'scan_retry': 'Reintentar cámara',
    'scan_cam_denied':
        'Cámara denegada — permite en Ajustes o vuelve y escribe el código.',
    'scan_cam_fail':
        'No arrancó la cámara ({err}). Reintenta o vuelve y escribe el código.',
    'scan_point': 'Apunta al código. Linterna arriba derecha.',
    'cat_choose': 'Toca para elegir',
    'cat_label': 'Categoría *',
    'cat_search': 'Buscar categorías',
    'cat_empty': 'Sin resultados — prueba otra palabra.',
    'cat_suggested': 'Sugerida',
    'sheet_size': 'Tamaño (ej. 12 oz, 1 pk)',
    'sheet_size_val': 'Tamaño: {size}',
    'sheet_promo_on': 'Promo SÍ (Tipo 02)',
    'sheet_promo': 'Promo (Tipo 02)',
    'sheet_was': 'Precio antes *',
    'sheet_ends': 'Termina (en inglés, ej. SUN 11/03)',
    'sheet_save': 'Ahorro (en inglés, ej. SAVE \$1.50)',
    'sheet_apply': 'Aplicar promo',
    'sheet_remove': 'Quitar',
    'toast_ok': 'Guardado.',
    'toast_fail': 'Falló. {detail}',
    'toast_offline': 'Sin conexión — revisa y reintenta.',
    'toast_session': 'Sesión vencida — inicia sesión (pestaña Cuenta).',
  };

  static const Map<AppLang, Map<String, String>> _strings = {
    AppLang.en: _en,
    AppLang.es: _es,
  };

  /// Key parity between locales (test-enforced).
  static Set<String> get enKeys => _en.keys.toSet();
  static Set<String> get esKeys => _es.keys.toSet();
}

// Shorthand used across screens: t('add_title'), tr.f(...).
String t(String key) => Lang.instance.t(key);
