-- ============================================================================
--  株式会社コニー 販売管理システム  PostgreSQL 17 スキーマ定義
--  v1.1  2026-09-03
--  要件定義書 第6章「データベース設計」に対応（全63テーブル）
--  未確定事項に依存する箇所は -- TODO(Qn) を付す。すべて暫定仕様で実装可能。
-- ============================================================================

SET client_encoding = 'UTF8';
SET timezone = 'Asia/Tokyo';

DROP SCHEMA IF EXISTS cony CASCADE;
CREATE SCHEMA cony;
SET search_path = cony, public;

-- ----------------------------------------------------------------------------
-- ドメイン定義
-- ----------------------------------------------------------------------------
CREATE DOMAIN money_amt AS NUMERIC(15,4);   -- 金額。端数処理は出力層で一元化
CREATE DOMAIN qty_num   AS NUMERIC(12,2);   -- 数量。負数を許容（販促品・値引・返品）
CREATE DOMAIN tax_rate  AS NUMERIC(5,2);    -- 税率（10.00 / 8.00 / 0.00）

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END; $$ LANGUAGE plpgsql;


-- ============================================================================
-- A. 共通基盤（10）
-- ============================================================================

-- (1) users ユーザー
CREATE TABLE users (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  login_id      VARCHAR(60)  NOT NULL UNIQUE,
  name          VARCHAR(120) NOT NULL,
  email         VARCHAR(255),
  password_hash TEXT         NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by    BIGINT,
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by    BIGINT
);
COMMENT ON TABLE users IS 'ユーザー（作業4名／閲覧20名）';

ALTER TABLE users ADD CONSTRAINT fk_users_created_by FOREIGN KEY (created_by) REFERENCES users(id);
ALTER TABLE users ADD CONSTRAINT fk_users_updated_by FOREIGN KEY (updated_by) REFERENCES users(id);

-- (2) roles ロール
CREATE TABLE roles (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code       VARCHAR(40)  NOT NULL UNIQUE,
  name       VARCHAR(80)  NOT NULL,
  sort_order INTEGER,
  is_active  BOOLEAN      NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE roles IS 'ロール（ADMIN／OPERATOR／ACCOUNTING／VIEWER）';

-- (3) user_roles ユーザーロール
CREATE TABLE user_roles (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id    BIGINT NOT NULL REFERENCES roles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by BIGINT REFERENCES users(id),
  UNIQUE (user_id, role_id)
);

-- (4) permissions 権限
CREATE TABLE permissions (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  function_id  VARCHAR(20)  NOT NULL,   -- 機能ID（M-01, O-01 …）
  action       VARCHAR(20)  NOT NULL,   -- view/create/update/delete/print
  name         VARCHAR(120) NOT NULL,
  is_sensitive BOOLEAN      NOT NULL DEFAULT false,  -- 原価・仕入単価・ロイヤリティ
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (function_id, action)
);
COMMENT ON TABLE permissions IS '機能単位の権限定義。is_sensitive は機微項目の参照制御に使用';

-- (5) role_permissions ロール権限
CREATE TABLE role_permissions (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  role_id       BIGINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id BIGINT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (role_id, permission_id)
);

-- (6) code_categories 区分カテゴリー
CREATE TABLE code_categories (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code       VARCHAR(60)  NOT NULL UNIQUE,   -- 例：PARTNER_DIVISION
  name       VARCHAR(120) NOT NULL,
  sort_order INTEGER,
  is_active  BOOLEAN      NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE code_categories IS '区分カテゴリー';

-- (7) codes 汎用区分
CREATE TABLE codes (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code_category_id BIGINT       NOT NULL REFERENCES code_categories(id),
  code             VARCHAR(40)  NOT NULL,
  name             VARCHAR(120) NOT NULL,
  sort_order       INTEGER,
  is_active        BOOLEAN      NOT NULL DEFAULT true,
  note             TEXT,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by       BIGINT REFERENCES users(id),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by       BIGINT REFERENCES users(id),
  UNIQUE (code_category_id, code)
);
COMMENT ON TABLE codes IS '汎用区分。ソースコードに固定値を持たない';
-- TODO(Q5) 初期データは 03-seed-data.sql（付録A）に定義。値の追加は画面から可能

-- (8) numbering_rules 採番ルール
CREATE TABLE numbering_rules (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target         VARCHAR(40) NOT NULL UNIQUE,
  prefix         VARCHAR(10),
  use_yyyymm     BOOLEAN     NOT NULL DEFAULT false,
  seq_length     SMALLINT    NOT NULL DEFAULT 5,
  current_value  BIGINT      NOT NULL DEFAULT 0,
  reset_unit     VARCHAR(10) NOT NULL DEFAULT 'month',
  last_reset_key VARCHAR(10),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_numbering_reset CHECK (reset_unit IN ('none','year','month'))
);
COMMENT ON TABLE numbering_rules IS '採番ルール。採番時は行を排他ロックする';
-- TODO(Q2) 出荷伝票番号の採番元確定後に設定を見直す

-- (9) attachments 添付ファイル
CREATE TABLE attachments (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ref_table       VARCHAR(40)  NOT NULL,
  ref_id          BIGINT       NOT NULL,
  file_name       VARCHAR(255) NOT NULL,
  storage_path    TEXT         NOT NULL,   -- 実体はDBに格納しない
  mime_type       VARCHAR(120),
  byte_size       BIGINT,
  is_print_target BOOLEAN      NOT NULL DEFAULT true,  -- 出荷指示時の印刷対象
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by      BIGINT REFERENCES users(id)
);
COMMENT ON TABLE attachments IS '添付ファイル（実体はストレージ、DBはメタデータのみ）';
CREATE INDEX ix_attachments_ref ON attachments (ref_table, ref_id);

-- (10) audit_logs 監査ログ
CREATE TABLE audit_logs (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     BIGINT REFERENCES users(id),
  acted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ref_table   VARCHAR(40) NOT NULL,
  ref_id      BIGINT,
  action      VARCHAR(20) NOT NULL,
  before_data JSONB,
  after_data  JSONB,
  CONSTRAINT ck_audit_action CHECK (action IN ('insert','update','delete'))
);
CREATE INDEX ix_audit_logs_ref ON audit_logs (ref_table, ref_id, acted_at DESC);


-- ============================================================================
-- B. 取引先（7）
-- ============================================================================

-- (11) media 媒体
CREATE TABLE media (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code       VARCHAR(40)  NOT NULL UNIQUE,
  name       VARCHAR(120) NOT NULL,
  sort_order INTEGER,
  is_active  BOOLEAN      NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE media IS '媒体';

-- (12) partner_categories 取引先カテゴリー
CREATE TABLE partner_categories (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code       VARCHAR(40)  NOT NULL UNIQUE,
  name       VARCHAR(120) NOT NULL,
  sort_order INTEGER,
  is_active  BOOLEAN      NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE partner_categories IS '取引先カテゴリー（確保数管理に使用）';

-- (13) sales_categories 販売カテゴリー
CREATE TABLE sales_categories (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code       VARCHAR(40)  NOT NULL UNIQUE,
  name       VARCHAR(120) NOT NULL,
  sort_order INTEGER,
  is_active  BOOLEAN      NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE sales_categories IS '販売カテゴリー（OA＝オンエア／カタログ／WEB 等）。貴社指示によりマスタ登録して選択';

-- (14) partners 取引先
CREATE TABLE partners (
  id                          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_code                VARCHAR(20)  NOT NULL UNIQUE,
  name1                       VARCHAR(120) NOT NULL,
  name2                       VARCHAR(120),
  short_name                  VARCHAR(60),
  is_customer                 BOOLEAN      NOT NULL DEFAULT false,
  is_supplier                 BOOLEAN      NOT NULL DEFAULT false,
  staff_user_id               BIGINT REFERENCES users(id),
  media_id                    BIGINT REFERENCES media(id),
  partner_category_id         BIGINT REFERENCES partner_categories(id),
  gross_margin_adjust_code_id BIGINT REFERENCES codes(id),   -- 粗利調整対象
  division_code_id            BIGINT REFERENCES codes(id),   -- 区分
  division2_code_id           BIGINT REFERENCES codes(id),   -- 区分2
  invoice_registration_no     VARCHAR(20),                   -- 適格請求書発行事業者番号
  monthly_invoice_code_id     BIGINT REFERENCES codes(id),   -- 毎月請求書発行
  digitized_code_id           BIGINT REFERENCES codes(id),   -- 電子化
  invoice_note                TEXT,                          -- 請求書事項
  shipping_fee_rule_code_id   BIGINT REFERENCES codes(id),   -- 送料3万以下・直送
  royalty_setting             VARCHAR(60),
  closing_day                 SMALLINT,                      -- 締め日（99＝月末）
  payment_month_offset        SMALLINT,
  payment_day                 SMALLINT,
  postal_code                 VARCHAR(8),
  address1                    VARCHAR(200),
  address2                    VARCHAR(200),
  tel                         VARCHAR(20),
  fax                         VARCHAR(20),
  is_active                   BOOLEAN     NOT NULL DEFAULT true,
  sort_order                  INTEGER,
  note                        TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_partners_role    CHECK (is_customer OR is_supplier),
  CONSTRAINT ck_partners_closing CHECK (closing_day IS NULL OR closing_day BETWEEN 1 AND 99),
  CONSTRAINT ck_partners_payday  CHECK (payment_day IS NULL OR payment_day BETWEEN 1 AND 99)
);
COMMENT ON TABLE partners IS '取引先（得意先・仕入先。Amazon等プラットフォームも1取引先として登録）';

-- (16) delivery_rules 納品ルール
CREATE TABLE delivery_rules (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code             VARCHAR(40)  NOT NULL UNIQUE,
  name             VARCHAR(120) NOT NULL,
  lead_time_days   SMALLINT,               -- 暫定
  allowed_weekdays VARCHAR(20),            -- 暫定（例：1,2,3,4,5）
  rule_body        TEXT,                   -- 自由記述。確定前でも運用可能
  sort_order       INTEGER,
  is_active        BOOLEAN      NOT NULL DEFAULT true,
  note             TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE delivery_rules IS '納品ルール';
-- TODO(Q3) 中身確定後に項目を構造化

-- (17) work_instructions 作業指示内容
CREATE TABLE work_instructions (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code             VARCHAR(40)  NOT NULL UNIQUE,
  name             VARCHAR(120) NOT NULL,
  instruction_body TEXT         NOT NULL,   -- 出荷指示書に印字し倉庫現場へ届ける
  sort_order       INTEGER,
  is_active        BOOLEAN      NOT NULL DEFAULT true,
  note             TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE work_instructions IS '作業指示内容（納品先ごとの梱包・荷札指示）';

-- (29) warehouses 倉庫（delivery_destinations との相互参照のため先に作成）
CREATE TABLE warehouses (
  id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  warehouse_code          VARCHAR(20) NOT NULL UNIQUE,
  short_name              VARCHAR(60) NOT NULL,
  division_code_id        BIGINT REFERENCES codes(id),
  is_consignment          BOOLEAN     NOT NULL DEFAULT false,
  partner_id              BIGINT REFERENCES partners(id),
  media_id                BIGINT REFERENCES media(id),
  delivery_destination_id BIGINT,     -- FK は delivery_destinations 作成後に付与
  postal_code VARCHAR(8), address1 VARCHAR(200), address2 VARCHAR(200),
  tel VARCHAR(20), fax VARCHAR(20),
  sort_order INTEGER,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE warehouses IS '倉庫（自社・委託）';

-- (15) delivery_destinations 納品先
CREATE TABLE delivery_destinations (
  id                       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id               BIGINT       NOT NULL REFERENCES partners(id),
  delivery_code            VARCHAR(20)  NOT NULL UNIQUE,
  name                     VARCHAR(120) NOT NULL,
  partner_delivery_no      VARCHAR(40),   -- 得意先が発行している納品先No
  consignee                VARCHAR(120),  -- 荷受人
  division_code_id         BIGINT REFERENCES codes(id),
  master_search_code_id    BIGINT REFERENCES codes(id),
  slip_issue_class_code_id BIGINT REFERENCES codes(id),
  delivery_note_print1     TEXT,
  delivery_note_print2     TEXT,
  work_instruction_id      BIGINT REFERENCES work_instructions(id),
  delivery_rule_id         BIGINT REFERENCES delivery_rules(id),
  default_warehouse_id     BIGINT REFERENCES warehouses(id),
  postal_code VARCHAR(8), address1 VARCHAR(200), address2 VARCHAR(200),
  tel VARCHAR(20), fax VARCHAR(20),
  sort_order INTEGER,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE delivery_destinations IS '納品先（1取引先に複数）';
CREATE INDEX ix_delivery_dest_partner ON delivery_destinations (partner_id);

ALTER TABLE warehouses
  ADD CONSTRAINT fk_warehouses_delivery_dest
  FOREIGN KEY (delivery_destination_id) REFERENCES delivery_destinations(id);


-- ============================================================================
-- C. 商品（11）
-- ============================================================================

-- (18) brands ブランド
CREATE TABLE brands (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(120) NOT NULL,
  sort_order INTEGER, is_active BOOLEAN NOT NULL DEFAULT true, note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE brands IS 'ブランド（LUXCEAR、芦屋美整体 等）';

-- (19) categories カテゴリー
CREATE TABLE categories (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(120) NOT NULL,
  sort_order INTEGER, is_active BOOLEAN NOT NULL DEFAULT true, note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE categories IS 'カテゴリー';

-- (20) product_classes 商品分類
CREATE TABLE product_classes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(120) NOT NULL,
  sort_order INTEGER, is_active BOOLEAN NOT NULL DEFAULT true, note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE product_classes IS '商品分類';

-- (21) colors カラー
CREATE TABLE colors (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(120) NOT NULL,
  sort_order INTEGER, is_active BOOLEAN NOT NULL DEFAULT true, note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE colors IS 'カラー。code は SKU コードの3〜4桁目に対応（例：03＝シフォンピンク）';

-- (22) sizes サイズ
CREATE TABLE sizes (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE, name VARCHAR(120) NOT NULL,
  sort_order INTEGER, is_active BOOLEAN NOT NULL DEFAULT true, note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE sizes IS 'サイズ。code は SKU コードの5〜6桁目に対応（例：06＝L）';

-- (23) products 商品
CREATE TABLE products (
  id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_code          VARCHAR(40)  NOT NULL UNIQUE,   -- 商品ID＝商品コード
  product_name          VARCHAR(200) NOT NULL,
  set_product_name      VARCHAR(200),
  brand_id              BIGINT REFERENCES brands(id),
  category_id           BIGINT REFERENCES categories(id),
  product_class_id      BIGINT REFERENCES product_classes(id),
  carton_qty            INTEGER,
  cost_price            money_amt   NOT NULL DEFAULT 0,  -- 閲覧者には非表示
  is_cost_undecided     BOOLEAN     NOT NULL DEFAULT false,
  royalty_class_code_id BIGINT REFERENCES codes(id),
  tax_rate              tax_rate    NOT NULL DEFAULT 10.00,
  division_code_id      BIGINT REFERENCES codes(id),
  display_code_id       BIGINT REFERENCES codes(id),
  is_set                BOOLEAN     NOT NULL DEFAULT false,  -- true は在庫を持たない
  sort_order INTEGER,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_products_tax CHECK (tax_rate IN (0.00, 8.00, 10.00))
);
COMMENT ON TABLE products IS '商品（品番レベル）';

-- (24) skus SKU
CREATE TABLE skus (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id    BIGINT      NOT NULL REFERENCES products(id),
  sku_code      VARCHAR(40) NOT NULL UNIQUE,   -- 例：FT1196-0306-100
  color_id      BIGINT REFERENCES colors(id),
  size_id       BIGINT REFERENCES sizes(id),
  pack_division VARCHAR(10),                   -- 100＝単品 / 200＝2枚組
  jan           VARCHAR(20),
  sort_order INTEGER,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE skus IS 'SKU（品番-カラー2桁+サイズ2桁-入数区分）';
CREATE INDEX ix_skus_product ON skus (product_id);
CREATE INDEX ix_skus_jan     ON skus (jan);

-- (25) set_headers セット
CREATE TABLE set_headers (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sku_id     BIGINT  NOT NULL UNIQUE REFERENCES skus(id),
  is_active  BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE set_headers IS 'セット登録。セット自体は在庫を持たない';

-- (26) set_components セット構成
CREATE TABLE set_components (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  set_header_id    BIGINT  NOT NULL REFERENCES set_headers(id) ON DELETE CASCADE,
  component_sku_id BIGINT  NOT NULL REFERENCES skus(id),
  qty              qty_num NOT NULL,
  sort_order       INTEGER,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by       BIGINT REFERENCES users(id),
  UNIQUE (set_header_id, component_sku_id),
  CONSTRAINT ck_set_components_qty CHECK (qty > 0)
);
COMMENT ON TABLE set_components IS 'セット構成。引当時に展開して各構成品から引き落とす';

-- (27) partner_products 取引先別商品
CREATE TABLE partner_products (
  id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id           BIGINT      NOT NULL REFERENCES partners(id),
  sku_id               BIGINT      NOT NULL REFERENCES skus(id),
  partner_product_code VARCHAR(60),   -- 取引先専用コード（例：Amazon TO-GXZN-60W8）
  partner_jan          VARCHAR(20),
  jan_code             VARCHAR(20),
  sales_name           VARCHAR(200),  -- 販売名
  sales_name2          VARCHAR(200),  -- 販売名_2
  unit_price           money_amt   NOT NULL DEFAULT 0,
  old_unit_price       money_amt,
  price_changed_date   DATE,
  cost_price           money_amt,     -- 閲覧者には非表示
  partner_color        VARCHAR(40),   -- 販社色
  partner_size         VARCHAR(40),   -- 販社サイズ
  color_name           VARCHAR(40),
  size_name            VARCHAR(40),
  is_royalty_excluded  BOOLEAN     NOT NULL DEFAULT false,
  royalty_rate         NUMERIC(7,4),  -- 調整点6-④：ここで設定
  product_class_id     BIGINT REFERENCES product_classes(id),
  memo                 TEXT,
  other                TEXT,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (partner_id, sku_id)
);
COMMENT ON TABLE partner_products IS '取引先別商品。Amazon SKU 等の専用コード読み替えの中核';
CREATE UNIQUE INDEX ux_partner_products_code
  ON partner_products (partner_id, partner_product_code)
  WHERE partner_product_code IS NOT NULL;

-- (28) partner_product_prices 取引先別単価履歴
CREATE TABLE partner_product_prices (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_product_id BIGINT    NOT NULL REFERENCES partner_products(id) ON DELETE CASCADE,
  unit_price         money_amt NOT NULL,
  valid_from         DATE      NOT NULL,
  valid_to           DATE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by         BIGINT REFERENCES users(id),
  CONSTRAINT ck_ppp_period CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
COMMENT ON TABLE partner_product_prices IS '取引先別単価履歴。過去伝票の再計算に使用';
CREATE INDEX ix_ppp_lookup ON partner_product_prices (partner_product_id, valid_from DESC);


-- ============================================================================
-- D. 在庫（7）※warehouses は B で作成済み
-- ============================================================================

-- (30) stocks 在庫
CREATE TABLE stocks (
  id                       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sku_id                   BIGINT      NOT NULL REFERENCES skus(id),
  warehouse_id             BIGINT      NOT NULL REFERENCES warehouses(id),
  lot_no                   VARCHAR(40) NOT NULL DEFAULT '',
  expiry_date              DATE,
  quality_code_id          BIGINT      NOT NULL REFERENCES codes(id),  -- 良品／不良／返品検品待ち
  qty_on_hand              qty_num     NOT NULL DEFAULT 0,
  qty_allocated            qty_num     NOT NULL DEFAULT 0,
  qty_available            qty_num     GENERATED ALWAYS AS (qty_on_hand - qty_allocated) STORED,
  consignment_product_code VARCHAR(40),
  consignment_qty          qty_num,
  cost_price               money_amt,   -- 閲覧者には非表示
  partner_id               BIGINT REFERENCES partners(id),
  planned_sales_month      DATE,
  planned_arrival_month    DATE,
  defective_class_id       BIGINT REFERENCES product_classes(id),
  note                     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (sku_id, warehouse_id, lot_no, quality_code_id),
  CONSTRAINT ck_stocks_on_hand   CHECK (qty_on_hand   >= 0),
  CONSTRAINT ck_stocks_allocated CHECK (qty_allocated >= 0),
  CONSTRAINT ck_stocks_available CHECK (qty_on_hand >= qty_allocated)
);
COMMENT ON TABLE stocks IS '在庫。有効在庫＝実在庫−引当済（生成列）。整合性はDBで担保する';
CREATE INDEX ix_stocks_sku_wh ON stocks (sku_id, warehouse_id);

-- (31) stock_movements 在庫移動履歴（追記専用）
CREATE TABLE stock_movements (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  stock_id      BIGINT      NOT NULL REFERENCES stocks(id),
  movement_type VARCHAR(20) NOT NULL,
  ref_table     VARCHAR(40) NOT NULL,
  ref_id        BIGINT      NOT NULL,
  qty           qty_num     NOT NULL,
  qty_before    qty_num     NOT NULL,
  qty_after     qty_num     NOT NULL,
  moved_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by    BIGINT REFERENCES users(id),
  CONSTRAINT ck_stock_mov_type CHECK (movement_type IN
    ('入荷','出荷','引当','引当解除','返品入庫','再生','不良振替','倉庫間移動','棚卸調整','廃棄'))
);
COMMENT ON TABLE stock_movements IS '在庫移動履歴。追記専用（UPDATE/DELETE を行わない）';
CREATE INDEX ix_stock_mov_stock ON stock_movements (stock_id, moved_at DESC);
CREATE INDEX ix_stock_mov_ref   ON stock_movements (ref_table, ref_id);

-- (33) reservations 確保数
CREATE TABLE reservations (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id        BIGINT  NOT NULL REFERENCES partners(id),
  sales_category_id BIGINT  NOT NULL REFERENCES sales_categories(id),
  sku_id            BIGINT  NOT NULL REFERENCES skus(id),
  period_from       DATE    NOT NULL,
  period_to         DATE    NOT NULL,
  reserved_qty      qty_num NOT NULL DEFAULT 0,
  consumed_qty      qty_num NOT NULL DEFAULT 0,
  note              TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (partner_id, sales_category_id, sku_id, period_from),
  CONSTRAINT ck_reservations_period CHECK (period_to >= period_from)
);
COMMENT ON TABLE reservations IS '取引先別確保数（取引先×販売カテゴリー×SKU×期間）';
-- TODO(Q12) 運用単位（放送日／月／期間）。期間保持のためいずれも表現可能

-- (34) receipts 入荷
CREATE TABLE receipts (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receipt_no          VARCHAR(30) NOT NULL UNIQUE,
  warehouse_id        BIGINT      NOT NULL REFERENCES warehouses(id),
  supplier_partner_id BIGINT REFERENCES partners(id),
  planned_date        DATE,
  received_date       DATE,
  status              VARCHAR(20) NOT NULL DEFAULT '指示',
  note                TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_receipts_status CHECK (status IN ('指示','入荷済','取消'))
);
COMMENT ON TABLE receipts IS '入荷（指示・実績）';

-- (35) receipt_lines 入荷明細
CREATE TABLE receipt_lines (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receipt_id  BIGINT  NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
  line_no     INTEGER NOT NULL,
  sku_id      BIGINT  NOT NULL REFERENCES skus(id),
  qty         qty_num NOT NULL,
  lot_no      VARCHAR(40),
  expiry_date DATE,
  cost_price  money_amt,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by  BIGINT REFERENCES users(id),
  UNIQUE (receipt_id, line_no)
);


-- ============================================================================
-- E. 受注・出荷（8）
-- ============================================================================

-- (36) sales_orders 受注
CREATE TABLE sales_orders (
  id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_no                VARCHAR(30) NOT NULL UNIQUE,
  order_type              VARCHAR(20) NOT NULL,   -- 卸／直送／通販
  partner_id              BIGINT      NOT NULL REFERENCES partners(id),
  delivery_destination_id BIGINT REFERENCES delivery_destinations(id),
  sales_category_id       BIGINT      NOT NULL REFERENCES sales_categories(id),
  trade_type              VARCHAR(10) NOT NULL DEFAULT '買取',
  po_no                   VARCHAR(40),
  order_date              DATE        NOT NULL,
  requested_delivery_date DATE,
  ship_from_warehouse_id  BIGINT REFERENCES warehouses(id),
  direct_name             VARCHAR(120),
  direct_kana             VARCHAR(120),
  direct_postal_code      VARCHAR(8),
  direct_address1         VARCHAR(200),
  direct_address2         VARCHAR(200),
  direct_tel              VARCHAR(20),
  shipping_remarks        TEXT,   -- 出荷備考 → 出荷指示書
  delivery_note_remarks   TEXT,   -- 納品書備考 → 納品書
  channel                 VARCHAR(30),
  external_order_id       BIGINT, -- FK は external_orders 作成後に付与
  status                  VARCHAR(20) NOT NULL DEFAULT '未確定',
  is_cancelled            BOOLEAN     NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_so_type   CHECK (order_type IN ('卸','直送','通販')),
  CONSTRAINT ck_so_trade  CHECK (trade_type IN ('委託','買取')),
  CONSTRAINT ck_so_status CHECK (status IN ('未確定','引当済','出荷指示済','出荷済','取消')),
  CONSTRAINT ck_so_dest   CHECK (order_type <> '卸' OR delivery_destination_id IS NOT NULL)
);
COMMENT ON TABLE sales_orders IS '受注。order_type により適用項目・検証・出力帳票が切り替わる';
CREATE INDEX ix_so_partner_date ON sales_orders (partner_id, order_date DESC);
CREATE INDEX ix_so_status ON sales_orders (status) WHERE is_cancelled = false;

-- (37) sales_order_lines 受注明細
CREATE TABLE sales_order_lines (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sales_order_id     BIGINT  NOT NULL REFERENCES sales_orders(id) ON DELETE CASCADE,
  line_no            INTEGER NOT NULL,
  parent_line_no     INTEGER,                 -- セット商品 → 同梱商品 の親子
  line_type          VARCHAR(20) NOT NULL,
  sku_id             BIGINT REFERENCES skus(id),
  partner_product_id BIGINT REFERENCES partner_products(id),
  item_name          VARCHAR(200) NOT NULL,
  qty                qty_num   NOT NULL,      -- 負数を許容（販促品・値引）
  unit_price         money_amt NOT NULL DEFAULT 0,
  tax_rate           tax_rate  NOT NULL DEFAULT 10.00,
  amount             money_amt NOT NULL DEFAULT 0,
  allocated_qty      qty_num   NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  UNIQUE (sales_order_id, line_no),
  CONSTRAINT ck_sol_type CHECK (line_type IN ('商品','セット商品','同梱商品','販促品','送料','値引')),
  CONSTRAINT ck_sol_sku  CHECK (line_type IN ('送料','値引') OR sku_id IS NOT NULL)
);
COMMENT ON TABLE sales_order_lines IS '受注明細。負数数量・非商品行を初日から許容する';

-- (38) shipments 出荷
CREATE TABLE shipments (
  id                          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shipment_no                 VARCHAR(30) NOT NULL UNIQUE,   -- 伝票管理番号（例：D0209475）
  sales_order_id              BIGINT REFERENCES sales_orders(id),
  warehouse_id                BIGINT      NOT NULL REFERENCES warehouses(id),
  planned_ship_date           DATE,
  ship_date                   DATE,
  carrier                     VARCHAR(60),
  tracking_no                 VARCHAR(40),
  shipping_label_type         VARCHAR(30),
  cod_amount                  money_amt,
  delivery_date_specified     DATE,
  delivery_time_slot          VARCHAR(20),
  consolidated_to_shipment_id BIGINT REFERENCES shipments(id),  -- 同梱先（自己参照）
  shipping_fee                money_amt,
  status                      VARCHAR(20) NOT NULL DEFAULT '未確定',
  confirmed_at                TIMESTAMPTZ,   -- 確定と印刷は分離
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_shipments_status CHECK (status IN ('未確定','確定済','印刷済','出荷済','削除'))
);
COMMENT ON TABLE shipments IS '出荷。同梱があるため受注と1:1とは限らない';
CREATE INDEX ix_shipments_wh_date ON shipments (warehouse_id, planned_ship_date);
CREATE INDEX ix_shipments_status  ON shipments (status);

-- (39) shipment_lines 出荷明細
CREATE TABLE shipment_lines (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shipment_id         BIGINT  NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
  line_no             INTEGER NOT NULL,
  sales_order_line_id BIGINT REFERENCES sales_order_lines(id),
  sku_id              BIGINT REFERENCES skus(id),
  item_name           VARCHAR(200) NOT NULL,
  qty                 qty_num   NOT NULL,
  unit_price          money_amt NOT NULL DEFAULT 0,
  tax_rate            tax_rate  NOT NULL DEFAULT 10.00,
  amount              money_amt NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  UNIQUE (shipment_id, line_no)
);

-- (32) allocations 引当
CREATE TABLE allocations (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sales_order_line_id BIGINT  NOT NULL REFERENCES sales_order_lines(id),
  stock_id            BIGINT  NOT NULL REFERENCES stocks(id),
  sku_id              BIGINT  NOT NULL REFERENCES skus(id),  -- セット展開後の構成品
  qty                 qty_num NOT NULL,
  status              VARCHAR(20) NOT NULL DEFAULT '引当中',
  released_at         TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_alloc_status CHECK (status IN ('引当中','出荷済','解除'))
);
COMMENT ON TABLE allocations IS '引当。削除時は解除して有効在庫を戻す（実在庫は不変）';
CREATE INDEX ix_alloc_line  ON allocations (sales_order_line_id);
CREATE INDEX ix_alloc_stock ON allocations (stock_id) WHERE status = '引当中';

-- (40) shipment_documents 帳票発行履歴
CREATE TABLE shipment_documents (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shipment_id   BIGINT      NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
  document_type VARCHAR(30) NOT NULL,
  printed_at    TIMESTAMPTZ,
  printed_by    BIGINT REFERENCES users(id),
  output_format VARCHAR(10),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_shipdoc_type CHECK (document_type IN
    ('出荷指示書','ピッキングリスト','納品書','添付ファイル'))
);
COMMENT ON TABLE shipment_documents IS '帳票発行履歴';

-- (41) returns 返品
CREATE TABLE returns (
  id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  return_no            VARCHAR(30) NOT NULL UNIQUE,
  return_type          VARCHAR(20) NOT NULL,
  partner_id           BIGINT REFERENCES partners(id),
  original_shipment_id BIGINT REFERENCES shipments(id),
  warehouse_id         BIGINT      NOT NULL REFERENCES warehouses(id),
  return_date          DATE        NOT NULL,
  return_amount        money_amt   NOT NULL DEFAULT 0,
  status               VARCHAR(20) NOT NULL DEFAULT '受付',
  note                 TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_returns_type   CHECK (return_type IN ('販社返品','顧客返品','プラットフォーム返金')),
  CONSTRAINT ck_returns_status CHECK (status IN ('受付','検品済','完了','取消'))
);
COMMENT ON TABLE returns IS '返品。return_amount は売掛残高一覧の「返品額」に集計される';

-- (42) return_lines 返品明細
CREATE TABLE return_lines (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  return_id  BIGINT  NOT NULL REFERENCES returns(id) ON DELETE CASCADE,
  line_no    INTEGER NOT NULL,
  sku_id     BIGINT  NOT NULL REFERENCES skus(id),
  qty        qty_num NOT NULL,
  unit_price money_amt NOT NULL DEFAULT 0,
  tax_rate   tax_rate  NOT NULL DEFAULT 10.00,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  UNIQUE (return_id, line_no)
);

-- (43) refurbishments 再生
CREATE TABLE refurbishments (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  return_line_id BIGINT      NOT NULL REFERENCES return_lines(id) ON DELETE CASCADE,
  inspected_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  good_qty       qty_num     NOT NULL DEFAULT 0,   -- 良品として在庫へ戻す
  defective_qty  qty_num     NOT NULL DEFAULT 0,   -- 不良在庫へ
  refurbish_cost money_amt,                        -- 暫定：保持のみ、会計連携なし
  note           TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_refurb_qty CHECK (good_qty >= 0 AND defective_qty >= 0)
);
COMMENT ON TABLE refurbishments IS '再生（検品して良品在庫へ戻す）';
-- TODO(Q11) 再生工程の費用計上、不良在庫の最終処理


-- ============================================================================
-- F. 請求・売掛（5）
-- ============================================================================

-- (44) invoices 請求
CREATE TABLE invoices (
  id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_no             VARCHAR(30) NOT NULL UNIQUE,
  partner_id             BIGINT      NOT NULL REFERENCES partners(id),
  closing_date           DATE        NOT NULL,
  period_from            DATE        NOT NULL,   -- 取引先別締め期間
  period_to              DATE        NOT NULL,
  prev_invoice_balance   money_amt NOT NULL DEFAULT 0,  -- 前回請求残高
  current_receipt_amount money_amt NOT NULL DEFAULT 0,  -- 今回入金額
  carryover_balance      money_amt NOT NULL DEFAULT 0,  -- 繰越残高
  shipment_amount        money_amt NOT NULL DEFAULT 0,  -- 出荷
  return_amount          money_amt NOT NULL DEFAULT 0,  -- 返品額
  unposted_10            money_amt NOT NULL DEFAULT 0,  -- 未計上10%
  unposted_8             money_amt NOT NULL DEFAULT 0,  -- 未計上8%
  fee_amount             money_amt NOT NULL DEFAULT 0,  -- 手数料
  adjust_10              money_amt NOT NULL DEFAULT 0,  -- 調整10%
  adjust_8               money_amt NOT NULL DEFAULT 0,  -- 調整8%
  shipping_fee_amount    money_amt NOT NULL DEFAULT 0,  -- 送料（3万円以下ルール）
  current_invoice_amount money_amt NOT NULL DEFAULT 0,  -- 当月請求額
  current_balance        money_amt NOT NULL DEFAULT 0,  -- 今回請求残高
  po_no                  VARCHAR(40),
  status                 VARCHAR(20) NOT NULL DEFAULT '未発行',
  issued_at              TIMESTAMPTZ,   -- 請求書には印刷しない
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (partner_id, period_to),
  CONSTRAINT ck_invoices_period CHECK (period_to >= period_from),
  CONSTRAINT ck_invoices_status CHECK (status IN ('未発行','発行済','取消'))
);
COMMENT ON TABLE invoices IS '請求（取引先別締め日）';
CREATE INDEX ix_invoices_partner ON invoices (partner_id, period_to DESC);
-- TODO(Q10) 未計上10%/8%、調整10%/8%、手数料の定義。暫定は手入力可

-- (45) invoice_lines 請求明細
CREATE TABLE invoice_lines (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id  BIGINT  NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  line_no     INTEGER NOT NULL,
  shipment_id BIGINT REFERENCES shipments(id),
  return_id   BIGINT REFERENCES returns(id),
  item_name   VARCHAR(200) NOT NULL,
  qty         qty_num   NOT NULL DEFAULT 0,
  unit_price  money_amt NOT NULL DEFAULT 0,
  tax_rate    tax_rate  NOT NULL DEFAULT 10.00,
  amount      money_amt NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  UNIQUE (invoice_id, line_no)
);

-- (46) invoice_tax_summaries 請求税率別内訳
CREATE TABLE invoice_tax_summaries (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id   BIGINT   NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  tax_rate     tax_rate NOT NULL,
  taxable_base money_amt NOT NULL DEFAULT 0,
  tax_amount   money_amt NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (invoice_id, tax_rate)
);
COMMENT ON TABLE invoice_tax_summaries IS '請求書上部に配置する税率別内訳の出力元';
-- TODO(Q8) 端数処理。暫定＝請求書単位・税率別・切捨て

-- (47) ar_ledgers 売掛元帳
CREATE TABLE ar_ledgers (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id      BIGINT NOT NULL REFERENCES partners(id),
  period_from     DATE   NOT NULL,
  period_to       DATE   NOT NULL,
  opening_balance money_amt NOT NULL DEFAULT 0,
  charge_amount   money_amt NOT NULL DEFAULT 0,
  receipt_amount  money_amt NOT NULL DEFAULT 0,
  closing_balance money_amt NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (partner_id, period_to)
);
COMMENT ON TABLE ar_ledgers IS '売掛元帳';

-- (48) cash_receipts 入金
CREATE TABLE cash_receipts (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id          BIGINT NOT NULL REFERENCES partners(id),
  receipt_date        DATE   NOT NULL,
  amount              money_amt NOT NULL,
  invoice_id          BIGINT REFERENCES invoices(id),
  applied_amount      money_amt NOT NULL DEFAULT 0,
  cash_transaction_id BIGINT,   -- FK は cash_transactions 作成後に付与
  note                TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE cash_receipts IS '入金と消込';


-- ============================================================================
-- G. 仕入・買掛・経費（6）
-- ============================================================================

-- (49) purchase_items 仕入マスタ
CREATE TABLE purchase_items (
  id                             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  purchase_code                  VARCHAR(60)  NOT NULL UNIQUE,  -- 例：Z-SA-1216-100
  item_name                      VARCHAR(200) NOT NULL,
  unit_cost                      money_amt    NOT NULL DEFAULT 0,  -- 閲覧者・作業者に非表示
  sales_price_setting_code_id    BIGINT REFERENCES codes(id),
  purchase_price_setting_code_id BIGINT REFERENCES codes(id),
  tax_exempt_code_id             BIGINT REFERENCES codes(id),
  new_tax_rate                   tax_rate,
  new_tax_class_code_id          BIGINT REFERENCES codes(id),
  category_id                    BIGINT REFERENCES categories(id),
  brand_id                       BIGINT REFERENCES brands(id),
  product_class_id               BIGINT REFERENCES product_classes(id),
  sort_order INTEGER,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  note       TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE purchase_items IS '仕入マスタ';

-- (50) purchases 仕入・経費
CREATE TABLE purchases (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  purchase_no         VARCHAR(30) NOT NULL UNIQUE,
  division            VARCHAR(10) NOT NULL,     -- 仕入／経費
  process_code_id     BIGINT REFERENCES codes(id),
  purchase_date       DATE        NOT NULL,
  currency            VARCHAR(3)  NOT NULL DEFAULT 'JPY',  -- 海外仕入に対応
  exchange_rate       NUMERIC(12,6),
  expense_code_id     BIGINT REFERENCES codes(id),
  delivery_date       DATE,
  payment_date1       DATE,
  payment_date2       DATE,
  supplier_partner_id BIGINT      NOT NULL REFERENCES partners(id),
  brand_id            BIGINT REFERENCES brands(id),
  product_class_id    BIGINT REFERENCES product_classes(id),
  total_amount        money_amt   NOT NULL DEFAULT 0,
  status              VARCHAR(20) NOT NULL DEFAULT '登録',
  note                TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_purchases_div    CHECK (division IN ('仕入','経費')),
  CONSTRAINT ck_purchases_status CHECK (status IN ('登録','確定','取消'))
);
COMMENT ON TABLE purchases IS '仕入・経費';
CREATE INDEX ix_purchases_supplier_date ON purchases (supplier_partner_id, purchase_date DESC);

-- (51) purchase_lines 仕入・経費明細
CREATE TABLE purchase_lines (
  id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  purchase_id             BIGINT  NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  line_no                 INTEGER NOT NULL,
  cost_division_code_id   BIGINT REFERENCES codes(id),      -- 費用区分
  purchase_item_id        BIGINT REFERENCES purchase_items(id),
  item_name               VARCHAR(200) NOT NULL,
  qty                     qty_num   NOT NULL DEFAULT 1,
  unit_cost               money_amt NOT NULL DEFAULT 0,
  subtotal                money_amt NOT NULL DEFAULT 0,
  tax_division_code_id    BIGINT REFERENCES codes(id),
  tax_rate                tax_rate  NOT NULL DEFAULT 10.00,
  target_brand_id         BIGINT REFERENCES brands(id),          -- 費用の配賦先
  target_product_class_id BIGINT REFERENCES product_classes(id),
  target_product_id       BIGINT REFERENCES products(id),
  warehouse_id            BIGINT REFERENCES warehouses(id),
  note                    TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  UNIQUE (purchase_id, line_no)
);

-- (52) ap_ledgers 買掛元帳
CREATE TABLE ap_ledgers (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id      BIGINT NOT NULL REFERENCES partners(id),
  period_from     DATE   NOT NULL,
  period_to       DATE   NOT NULL,
  opening_balance money_amt NOT NULL DEFAULT 0,
  charge_amount   money_amt NOT NULL DEFAULT 0,
  payment_amount  money_amt NOT NULL DEFAULT 0,
  closing_balance money_amt NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (partner_id, period_to)
);
COMMENT ON TABLE ap_ledgers IS '買掛元帳';

-- (53) cash_payments 出金
CREATE TABLE cash_payments (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id          BIGINT NOT NULL REFERENCES partners(id),
  payment_date        DATE   NOT NULL,
  amount              money_amt NOT NULL,
  purchase_id         BIGINT REFERENCES purchases(id),
  applied_amount      money_amt NOT NULL DEFAULT 0,
  cash_transaction_id BIGINT,   -- FK は cash_transactions 作成後に付与
  note                TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE cash_payments IS '出金と消込';

-- (54) cash_transactions 入出金
CREATE TABLE cash_transactions (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cash_transaction_no VARCHAR(30) NOT NULL UNIQUE,
  currency            VARCHAR(3)  NOT NULL DEFAULT 'JPY',
  target_month        DATE        NOT NULL,
  scheduled_date      DATE,
  division            VARCHAR(10) NOT NULL,          -- 入金／出金
  type_code_id        BIGINT REFERENCES codes(id),
  sales_staff_name    VARCHAR(60),
  partner_id          BIGINT REFERENCES partners(id),
  partner_contact     VARCHAR(60),
  amount              money_amt NOT NULL DEFAULT 0,
  bill_due_date1      DATE,      bill_amount1 money_amt,   -- 手形決済日①／手形①
  bill_due_date2      DATE,      bill_amount2 money_amt,   -- 手形決済日②／手形②
  transaction_date    DATE,
  transfer_amount     money_amt,  -- 振込
  cash_amount         money_amt,  -- 現金
  fee_amount          money_amt,  -- 手数料
  collection_amount   money_amt,  -- 集金
  offset_amount       money_amt,  -- 相殺
  check_amount        money_amt,  -- 小切手
  overseas_usd        money_amt,  -- 海外送金$
  overseas_cny        money_amt,  -- 海外送金CNY
  expense_id          BIGINT,
  note                TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_cash_div CHECK (division IN ('入金','出金'))
);
COMMENT ON TABLE cash_transactions IS '入出金（手形2本立て・相殺・小切手・集金・海外送金に対応）';
CREATE INDEX ix_cash_partner_month ON cash_transactions (partner_id, target_month);

ALTER TABLE cash_receipts ADD CONSTRAINT fk_cash_receipts_txn
  FOREIGN KEY (cash_transaction_id) REFERENCES cash_transactions(id);
ALTER TABLE cash_payments ADD CONSTRAINT fk_cash_payments_txn
  FOREIGN KEY (cash_transaction_id) REFERENCES cash_transactions(id);


-- ============================================================================
-- H. ロイヤリティ（3）
-- ============================================================================

-- (55) royalty_rules ロイヤリティ設定
CREATE TABLE royalty_rules (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_id     BIGINT REFERENCES brands(id),
  product_id   BIGINT REFERENCES products(id),
  partner_id   BIGINT REFERENCES partners(id),
  calc_base    VARCHAR(20) NOT NULL DEFAULT '出荷',   -- 売上／出荷／入金
  rate         NUMERIC(7,4),
  fixed_amount money_amt,
  valid_from   DATE NOT NULL,
  valid_to     DATE,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  sort_order   INTEGER,
  note         TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_royalty_base   CHECK (calc_base IN ('売上','出荷','入金')),
  CONSTRAINT ck_royalty_amount CHECK (rate IS NOT NULL OR fixed_amount IS NOT NULL),
  CONSTRAINT ck_royalty_period CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
COMMENT ON TABLE royalty_rules IS 'ロイヤリティ設定。料率・定額・計算基準をすべて設定値とする';
-- TODO(Q9) 計算式確定後は本マスタの設定変更のみで対応可能

-- (56) royalty_calculations ロイヤリティ計算
CREATE TABLE royalty_calculations (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_month  DATE        NOT NULL,
  partner_id    BIGINT REFERENCES partners(id),
  total_amount  money_amt   NOT NULL DEFAULT 0,
  status        VARCHAR(20) NOT NULL DEFAULT '計算済',
  calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  UNIQUE (target_month, partner_id),
  CONSTRAINT ck_royalty_calc_status CHECK (status IN ('計算済','確定','取消'))
);

-- (57) royalty_calculation_lines ロイヤリティ計算明細
CREATE TABLE royalty_calculation_lines (
  id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  royalty_calculation_id BIGINT NOT NULL REFERENCES royalty_calculations(id) ON DELETE CASCADE,
  sku_id                 BIGINT NOT NULL REFERENCES skus(id),
  base_amount            money_amt NOT NULL DEFAULT 0,
  rate                   NUMERIC(7,4),
  royalty_amount         money_amt NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================================
-- I. 連携・分析（6）
-- ============================================================================

-- (58) import_batches 取込バッチ
CREATE TABLE import_batches (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  import_type   VARCHAR(30)  NOT NULL,   -- OMS_ORDER / AMAZON_TRANSACTION
  file_name     VARCHAR(255) NOT NULL,
  imported_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  imported_by   BIGINT REFERENCES users(id),
  total_count   INTEGER      NOT NULL DEFAULT 0,
  success_count INTEGER      NOT NULL DEFAULT 0,
  error_count   INTEGER      NOT NULL DEFAULT 0,
  status        VARCHAR(20)  NOT NULL DEFAULT '完了',
  note          TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_import_type   CHECK (import_type IN ('OMS_ORDER','AMAZON_TRANSACTION')),
  CONSTRAINT ck_import_status CHECK (status IN ('完了','一部エラー','取消'))
);
COMMENT ON TABLE import_batches IS '取込バッチ。バッチ単位で取消できる（出荷確定済みは不可）';

-- (59) external_orders 外部受注
CREATE TABLE external_orders (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  import_batch_id    BIGINT      NOT NULL REFERENCES import_batches(id),
  channel            VARCHAR(30) NOT NULL,
  external_order_no  VARCHAR(60) NOT NULL,
  ordered_at         TIMESTAMPTZ,
  payment_method     VARCHAR(60),
  payment_fee        money_amt,
  total_amount       money_amt,              -- 合計請求金額（検算用）
  consolidated_to    VARCHAR(60),            -- 同梱先の受注番号
  slip_management_no VARCHAR(30),            -- 伝票管理番号（D02094xx）
  tracking_no        VARCHAR(40),
  warehouse_name     VARCHAR(60),
  ship_date          DATE,
  sales_order_id     BIGINT REFERENCES sales_orders(id),
  raw_data           JSONB       NOT NULL,   -- 取り込んだCSV行の原本
  status             VARCHAR(20) NOT NULL DEFAULT '取込済',
  error_message      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (channel, external_order_no),       -- 二重取込による二重計上を防止
  CONSTRAINT ck_ext_status CHECK (status IN ('取込済','変換済','エラー','取消'))
);
COMMENT ON TABLE external_orders IS 'OMS受注の原本。冪等性は (channel, external_order_no) で担保';
CREATE INDEX ix_ext_orders_batch ON external_orders (import_batch_id);
CREATE INDEX ix_ext_orders_raw   ON external_orders USING GIN (raw_data);
-- TODO(Q1) 「受注取込」か「出荷済み実績取込」かはモード設定で切替

ALTER TABLE sales_orders ADD CONSTRAINT fk_so_external_order
  FOREIGN KEY (external_order_id) REFERENCES external_orders(id);

-- (60) external_order_lines 外部受注明細
CREATE TABLE external_order_lines (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  external_order_id BIGINT  NOT NULL REFERENCES external_orders(id) ON DELETE CASCADE,
  line_no           INTEGER NOT NULL,
  line_type         VARCHAR(20),
  item_name         VARCHAR(200),
  qty               qty_num,                -- 販促品は -1
  unit_price        money_amt,
  external_sku_code VARCHAR(60),            -- 自社商品コード（例：FT1196-0306-100）
  sku_id            BIGINT REFERENCES skus(id),
  raw_data          JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (external_order_id, line_no)
);

-- (61) platform_transactions プラットフォーム取引
CREATE TABLE platform_transactions (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  import_batch_id   BIGINT      NOT NULL REFERENCES import_batches(id),
  platform          VARCHAR(30) NOT NULL,
  settlement_no     VARCHAR(40),
  transaction_type  VARCHAR(40) NOT NULL,
  transaction_at    TIMESTAMPTZ,
  external_order_no VARCHAR(60),
  external_sku_code VARCHAR(60),                -- Amazon SKU（TO-GXZN-60W8 等）
  sku_id            BIGINT REFERENCES skus(id), -- 得意先別商品マスタ経由で解決
  description       TEXT,
  qty               qty_num,
  product_sales     money_amt, product_sales_tax  money_amt,
  shipping_fee      money_amt, shipping_tax       money_amt,
  points_cost       money_amt,
  promo_discount    money_amt, promo_discount_tax money_amt,
  commission_fee    money_amt, fba_fee money_amt,
  other_fee         money_amt, other_amount money_amt,
  total_amount      money_amt,
  status            VARCHAR(30),
  raw_data          JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE platform_transactions IS 'Amazon等の決済レポート。売上／返品／経費／入金の4系統へ振り分ける';
CREATE INDEX ix_pt_type ON platform_transactions (platform, transaction_type, transaction_at);
-- TODO(Q14) 手数料の計上先・入金消込ルール

-- (62) sales_schedules 販売スケジュール
CREATE TABLE sales_schedules (
  id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  partner_id            BIGINT REFERENCES partners(id),
  sales_category_id     BIGINT REFERENCES sales_categories(id),
  sku_id                BIGINT REFERENCES skus(id),
  planned_sales_month   DATE,
  planned_arrival_month DATE,
  planned_qty           qty_num,
  note                  TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id)
);
COMMENT ON TABLE sales_schedules IS '販売スケジュール';
-- TODO(Q13) 現行画面の確認後に項目を確定

-- (63) saved_queries 保存クエリ
CREATE TABLE saved_queries (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name        VARCHAR(120) NOT NULL,
  target      VARCHAR(40)  NOT NULL,
  conditions  JSONB        NOT NULL,
  share_scope VARCHAR(20)  NOT NULL DEFAULT 'private',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_by BIGINT REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id),
  CONSTRAINT ck_saved_scope CHECK (share_scope IN ('private','shared'))
);
COMMENT ON TABLE saved_queries IS '汎用クエリ集計の条件保存';


-- ============================================================================
-- updated_at トリガの一括付与
-- ============================================================================
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT DISTINCT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
     WHERE n.nspname = 'cony'
       AND c.relkind = 'r'
       AND a.attname = 'updated_at'
       AND a.attnum > 0
       AND NOT a.attisdropped
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON cony.%1$I
         FOR EACH ROW EXECUTE FUNCTION cony.set_updated_at()', t);
  END LOOP;
END $$;

-- ============================================================================
-- 在庫移動履歴を追記専用にする（UPDATE/DELETE を拒否）
-- ============================================================================
CREATE OR REPLACE FUNCTION deny_modification() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% は追記専用テーブルです（UPDATE/DELETE は許可されません）', TG_TABLE_NAME;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stock_movements_immutable
  BEFORE UPDATE OR DELETE ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION deny_modification();

CREATE TRIGGER trg_audit_logs_immutable
  BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION deny_modification();

-- ============================================================================
--  以上（63テーブル）
-- ============================================================================
