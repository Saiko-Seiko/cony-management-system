-- ============================================================================
--  株式会社コニー 販売管理システム  初期データ
--  v1.0  2026-09-03
--  要件定義書 付録A「区分値マスタ初期データ」／付録B「権限マトリクス」に対応
--  ※印の値は貴社確認事項（Q5）。画面から追加・変更できるため開発に支障はない。
-- ============================================================================

SET client_encoding = 'UTF8';
SET search_path = cony, public;

-- ----------------------------------------------------------------------------
-- 1. 区分カテゴリー
-- ----------------------------------------------------------------------------
INSERT INTO code_categories (code, name, sort_order) VALUES
  ('QUALITY_DIVISION',       '品質区分',            10),
  ('PARTNER_DIVISION',       '取引先区分',          20),
  ('PARTNER_DIVISION2',      '取引先区分2',         21),
  ('GROSS_MARGIN_ADJUST',    '粗利調整対象',        22),
  ('MONTHLY_INVOICE',        '毎月請求書発行',      23),
  ('DIGITIZED',              '電子化',              24),
  ('SHIPPING_FEE_RULE',      '送料3万以下・直送',   25),
  ('DELIVERY_DIVISION',      '納品先区分',          30),
  ('MASTER_SEARCH_DISPLAY',  'マスタ検索表示区分',  31),
  ('SLIP_ISSUE_CLASS',       '伝票発行分類',        32),
  ('PRODUCT_DIVISION',       '商品区分',            40),
  ('PRODUCT_DISPLAY',        '商品表示',            41),
  ('ROYALTY_CLASS',          'ロイヤリティ区分',    42),
  ('WAREHOUSE_DIVISION',     '倉庫区分',            50),
  ('TAX_DIVISION',           '税区分',              60),
  ('EXPENSE_DIVISION',       '経費区分',            61),
  ('COST_DIVISION',          '費用区分',            62),
  ('SALES_PRICE_SETTING',    '売上単価設定区分',    63),
  ('PURCHASE_PRICE_SETTING', '仕入単価設定区分',    64),
  ('TAX_EXEMPT',             '非課税区分',          65),
  ('NEW_TAX_CLASS',          '新税分類',            66),
  ('CASH_TYPE',              '入出金種類',          70),
  ('PROCESS',                '処理',                71);

-- ----------------------------------------------------------------------------
-- 2. 区分値
-- ----------------------------------------------------------------------------
-- 品質区分（在庫。システム動作に必須）
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('GOOD',      '良品',          10),
  ('DEFECTIVE', '不良',          20),
  ('PENDING',   '返品検品待ち',  30)
) AS v(code, name, so) WHERE code_categories.code = 'QUALITY_DIVISION';

-- 取引先区分 ※要確認
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('TV',       '販社（テレビ通販）', 10),
  ('CATALOG',  '販社（カタログ）',   20),
  ('EC',       '通販（EC）',         30),
  ('STORE',    '実店舗',             40),
  ('SUPPLIER', '仕入先',             50),
  ('OTHER',    'その他',             90)
) AS v(code, name, so) WHERE code_categories.code = 'PARTNER_DIVISION';

-- 粗利調整対象
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('TARGET',     '対象',   10),
  ('NOT_TARGET', '対象外', 20)
) AS v(code, name, so) WHERE code_categories.code = 'GROSS_MARGIN_ADJUST';

-- 毎月請求書発行
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('ISSUE',     '発行する',   10),
  ('NOT_ISSUE', '発行しない', 20)
) AS v(code, name, so) WHERE code_categories.code = 'MONTHLY_INVOICE';

-- 電子化
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('DIGITAL', '電子', 10),
  ('PAPER',   '紙',   20)
) AS v(code, name, so) WHERE code_categories.code = 'DIGITIZED';

-- 送料3万以下・直送
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('CHARGE',      '請求する',         10),
  ('NO_CHARGE',   '請求しない',       20),
  ('DIRECT_ONLY', '直送のみ請求する', 30)
) AS v(code, name, so) WHERE code_categories.code = 'SHIPPING_FEE_RULE';

-- 商品区分 ※要確認
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('MAIN',      '本体',   10),
  ('ACCESSORY', '付属品', 20),
  ('PROMO',     '販促品', 30),
  ('OTHER',     'その他', 90)
) AS v(code, name, so) WHERE code_categories.code = 'PRODUCT_DIVISION';

-- 商品表示
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('SHOW', '表示する',   10),
  ('HIDE', '表示しない', 20)
) AS v(code, name, so) WHERE code_categories.code = 'PRODUCT_DISPLAY';

-- ロイヤリティ区分
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('MACHINE',    '機械商品', 10),
  ('NOT_TARGET', '対象外',   20)
) AS v(code, name, so) WHERE code_categories.code = 'ROYALTY_CLASS';

-- 倉庫区分
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('OWN',         '自社倉庫', 10),
  ('CONSIGNMENT', '委託倉庫', 20),
  ('EXTERNAL',    '外部倉庫', 30)
) AS v(code, name, so) WHERE code_categories.code = 'WAREHOUSE_DIVISION';

-- 税区分
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('TAX10',    '課税10%', 10),
  ('TAX8',     '軽減8%',  20),
  ('EXEMPT',   '非課税',  30),
  ('NON_TAX',  '不課税',  40)
) AS v(code, name, so) WHERE code_categories.code = 'TAX_DIVISION';

-- 経費区分 ※要確認（Amazon 関連は Q14 の暫定仕様）
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('AD',         '広告費',           10),
  ('LOGISTICS',  '物流費',           20),
  ('PROMOTION',  '販促費',           30),
  ('AMZ_FEE',    'Amazon手数料',     40),
  ('AMZ_AD',     'Amazon広告費',     50),
  ('FBA_FEE',    'FBA手数料',        60),
  ('OTHER',      'その他',           90)
) AS v(code, name, so) WHERE code_categories.code = 'EXPENSE_DIVISION';

-- 非課税区分
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('TAXABLE', '課税',   10),
  ('EXEMPT',  '非課税', 20)
) AS v(code, name, so) WHERE code_categories.code = 'TAX_EXEMPT';

-- 入出金種類
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('AR_RECEIPT', '売掛入金', 10),
  ('AP_PAYMENT', '買掛支払', 20),
  ('EXPENSE',    '経費支払', 30),
  ('OTHER',      'その他',   90)
) AS v(code, name, so) WHERE code_categories.code = 'CASH_TYPE';

-- 処理
INSERT INTO codes (code_category_id, code, name, sort_order)
SELECT id, v.code, v.name, v.so FROM code_categories, (VALUES
  ('PENDING', '未処理', 10),
  ('DONE',    '処理済', 20)
) AS v(code, name, so) WHERE code_categories.code = 'PROCESS';

-- ※以下は貴社確認後に登録する（Q5）
--   PARTNER_DIVISION2 / DELIVERY_DIVISION / MASTER_SEARCH_DISPLAY /
--   SLIP_ISSUE_CLASS / COST_DIVISION / SALES_PRICE_SETTING /
--   PURCHASE_PRICE_SETTING / NEW_TAX_CLASS


-- ----------------------------------------------------------------------------
-- 3. 販売カテゴリー（OA／カタログ／WEB）
-- ----------------------------------------------------------------------------
INSERT INTO sales_categories (code, name, sort_order) VALUES
  ('OA',      'OA（オンエア）', 10),
  ('CATALOG', 'カタログ',       20),
  ('WEB',     'WEB',            30);

-- ----------------------------------------------------------------------------
-- 4. ロール
-- ----------------------------------------------------------------------------
INSERT INTO roles (code, name, sort_order) VALUES
  ('ADMIN',      '管理者', 10),
  ('OPERATOR',   '作業者', 20),
  ('ACCOUNTING', '経理',   30),
  ('VIEWER',     '閲覧者', 40);

-- ----------------------------------------------------------------------------
-- 5. 権限（機能 × 操作）
-- ----------------------------------------------------------------------------
INSERT INTO permissions (function_id, action, name, is_sensitive)
SELECT f.fid, a.act, f.fname || '：' || a.aname, f.sens
FROM (VALUES
  ('M-01','取引先マスタ',        false),
  ('M-05','納品先マスタ',        false),
  ('M-08','商品マスタ',          true ),   -- 原価を含む
  ('M-09','SKUコードマスタ',     false),
  ('M-10','セット登録マスタ',    false),
  ('M-11','得意先別商品マスタ',  true ),   -- 原価・ロイヤリティを含む
  ('M-14','倉庫マスタ',          false),
  ('M-15','仕入マスタ',          true ),   -- 仕入単価を含む
  ('M-16','汎用区分マスタ',      false),
  ('M-17','ユーザー・権限',      true ),
  ('O-01','受注登録',            false),
  ('O-03','受注一覧',            false),
  ('S-01','在庫表',              false),
  ('S-03','入荷登録',            false),
  ('S-05','入出荷履歴',          false),
  ('S-08','取引先別確保数',      false),
  ('D-01','出荷指示',            false),
  ('D-03','帳票一括印刷',        false),
  ('R-01','返品・再生',          false),
  ('B-01','締め処理',            false),
  ('B-02','請求書発行',          false),
  ('B-04','売掛残高一覧',        false),
  ('B-05','入金登録・消込',      false),
  ('P-01','仕入・経費登録',      true ),
  ('P-03','買掛残高一覧',        true ),
  ('C-01','入出金処理',          true ),
  ('Y-02','ロイヤリティ計算',    true ),
  ('A-01','販売実績管理',        false),
  ('A-03','汎用クエリ集計',      false),
  ('I-01','CSV取込',             false)
) AS f(fid, fname, sens),
(VALUES
  ('view','参照'), ('create','登録'), ('update','更新'),
  ('delete','削除'), ('print','印刷')
) AS a(act, aname);

-- ----------------------------------------------------------------------------
-- 6. ロール権限（付録B の権限マトリクス）
-- ----------------------------------------------------------------------------
-- 管理者：全権限
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p WHERE r.code = 'ADMIN';

-- 閲覧者：機微でない機能の参照のみ
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
 WHERE r.code = 'VIEWER' AND p.action = 'view' AND p.is_sensitive = false;

-- 作業者：機微でない機能の全操作＋機微機能の参照（ただし M-15/P-01/C-01/Y-02 を除く）
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
 WHERE r.code = 'OPERATOR'
   AND (
        (p.is_sensitive = false)
     OR (p.is_sensitive = true AND p.action = 'view'
         AND p.function_id NOT IN ('M-15','P-01','C-01','Y-02','M-17'))
   );

-- 経理：金額系の全操作＋その他の参照
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
 WHERE r.code = 'ACCOUNTING'
   AND (
        p.function_id IN ('M-15','B-01','B-02','B-04','B-05','P-01','P-03','C-01','Y-02','A-01','A-03')
     OR p.action = 'view'
   )
   AND p.function_id <> 'M-17';

-- ----------------------------------------------------------------------------
-- 7. 採番ルール（要件定義書 6.8）
-- ----------------------------------------------------------------------------
INSERT INTO numbering_rules (target, prefix, use_yyyymm, seq_length, reset_unit) VALUES
  ('sales_order',      'SO', true,  5, 'month'),
  ('shipment',         'D',  false, 7, 'none'),
  ('receipt',          'RC', true,  5, 'month'),
  ('return',           'RT', true,  5, 'month'),
  ('invoice',          'IV', true,  4, 'month'),
  ('purchase',         'PU', true,  5, 'month'),
  ('cash_transaction', NULL, false, 8, 'none'),
  ('delivery_code',    NULL, false, 8, 'none'),
  ('warehouse_code',   NULL, false, 4, 'none'),
  ('purchase_item',    NULL, false, 8, 'none');

-- ----------------------------------------------------------------------------
-- 8. 倉庫（実データより）
-- ----------------------------------------------------------------------------
INSERT INTO warehouses (warehouse_code, short_name, is_consignment, division_code_id, sort_order)
SELECT v.wc, v.nm, false,
       (SELECT c.id FROM codes c
          JOIN code_categories cc ON cc.id = c.code_category_id
         WHERE cc.code = 'WAREHOUSE_DIVISION' AND c.code = 'OWN'),
       v.so
FROM (VALUES
  ('0001', 'コニー倉庫(EC)',        10),
  ('0002', 'コニー倉庫(交換・EC)',  20),
  ('0003', 'コニー倉庫(補正下着他)',30),
  ('0004', 'コニー倉庫(コニーストア)', 40)
) AS v(wc, nm, so);

-- ----------------------------------------------------------------------------
-- 9. 初期ユーザー（本番投入時にパスワードを変更すること）
-- ----------------------------------------------------------------------------
INSERT INTO users (login_id, name, password_hash, is_active)
VALUES ('admin', 'システム管理者', '$2b$12$CHANGE_THIS_ON_DEPLOY', true);

INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r WHERE u.login_id = 'admin' AND r.code = 'ADMIN';

-- ============================================================================
--  以上
-- ============================================================================
