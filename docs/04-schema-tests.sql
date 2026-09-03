-- ============================================================================
--  株式会社コニー 販売管理システム  スキーマ受入テスト
--  v1.0  2026-09-03
--  02-schema.sql → 03-seed-data.sql を適用した直後の空データベースで実行する。
--  1件でも失敗すると ERROR で停止する（成功時のみ最後まで到達する）。
--  失敗時の独自エラーコード：TF001
-- ============================================================================

SET client_encoding = 'UTF8';
SET search_path = cony, public;

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- T01〜T04  スキーマ・初期データの整合
-- ----------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.tables
   WHERE table_schema='cony' AND table_type='BASE TABLE';
  IF n <> 63 THEN
    RAISE EXCEPTION 'T01 失敗: テーブル数が % 件（期待 63 件）', n USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T01 OK  テーブル数 63';

  SELECT count(*) INTO n FROM pg_type t JOIN pg_namespace ns ON ns.oid=t.typnamespace
   WHERE ns.nspname='cony' AND t.typtype='d' AND t.typname IN ('money_amt','qty_num','tax_rate');
  IF n <> 3 THEN
    RAISE EXCEPTION 'T02 失敗: ドメイン数が % 件（期待 3 件）', n USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T02 OK  ドメイン money_amt / qty_num / tax_rate';

  SELECT count(*) INTO n FROM code_categories;
  IF n <> 23 THEN RAISE EXCEPTION 'T03 失敗: 区分カテゴリー % 件（期待 23 件）', n USING ERRCODE='TF001'; END IF;
  SELECT count(*) INTO n FROM sales_categories;
  IF n <> 3  THEN RAISE EXCEPTION 'T03 失敗: 販売カテゴリー % 件（期待 3 件）', n USING ERRCODE='TF001'; END IF;
  SELECT count(*) INTO n FROM roles;
  IF n <> 4  THEN RAISE EXCEPTION 'T03 失敗: ロール % 件（期待 4 件）', n USING ERRCODE='TF001'; END IF;
  SELECT count(*) INTO n FROM warehouses;
  IF n <> 4  THEN RAISE EXCEPTION 'T03 失敗: 倉庫 % 件（期待 4 件）', n USING ERRCODE='TF001'; END IF;
  SELECT count(*) INTO n FROM numbering_rules;
  IF n <> 10 THEN RAISE EXCEPTION 'T03 失敗: 採番ルール % 件（期待 10 件）', n USING ERRCODE='TF001'; END IF;
  RAISE NOTICE 'T03 OK  初期データ（区分23／販売カテゴリー3／ロール4／倉庫4／採番10）';

  SELECT count(*) INTO n FROM codes c JOIN code_categories cc ON cc.id=c.code_category_id
   WHERE cc.code='QUALITY_DIVISION';
  IF n <> 3 THEN RAISE EXCEPTION 'T04 失敗: 品質区分 % 件（期待 3 件）', n USING ERRCODE='TF001'; END IF;
  RAISE NOTICE 'T04 OK  品質区分 良品／不良／返品検品待ち';
END $$;

-- ----------------------------------------------------------------------------
-- テスト用データの投入
-- ----------------------------------------------------------------------------
INSERT INTO media (code, name) VALUES ('TV', 'テレビ');
INSERT INTO brands (code, name) VALUES ('LX', 'LUXCEAR'), ('AS', '芦屋美整体');
INSERT INTO colors (code, name) VALUES ('03', 'シフォンピンク'), ('02', 'ベージュ');
INSERT INTO sizes  (code, name) VALUES ('06', 'L'), ('04', 'M');

INSERT INTO partners (partner_code, name1, is_customer, is_supplier, closing_day) VALUES
  ('P001', 'テスト販社',   true,  false, 99),
  ('AMZN', 'Amazon',       true,  false, 99),
  ('S001', 'テスト仕入先', false, true,  99);

INSERT INTO delivery_destinations (partner_id, delivery_code, name, partner_delivery_no, default_warehouse_id)
SELECT p.id, 'D001', 'テスト納品先', 'CL-0001', w.id
  FROM partners p, warehouses w
 WHERE p.partner_code='P001' AND w.warehouse_code='0001';

INSERT INTO products (product_code, product_name, brand_id, cost_price, tax_rate, is_set)
SELECT 'FT1196', '滑らかシームレスエアーHOT', b.id, 1200, 10.00, false FROM brands b WHERE b.code='LX';
INSERT INTO products (product_code, product_name, brand_id, cost_price, tax_rate, is_set)
SELECT 'FT1198', '滑らかシームレスエアー10', b.id, 1500, 10.00, false FROM brands b WHERE b.code='LX';
INSERT INTO products (product_code, product_name, brand_id, cost_price, tax_rate, is_set)
SELECT 'FT1198-1', '滑らかシームレスエアー10 2枚組', b.id, 0, 10.00, true FROM brands b WHERE b.code='LX';
INSERT INTO products (product_code, product_name, brand_id, cost_price, tax_rate, is_set)
SELECT 'CS2420', 'LUXCEAR Fornez PRO', b.id, 3000, 10.00, false FROM brands b WHERE b.code='LX';

INSERT INTO skus (product_id, sku_code, color_id, size_id, pack_division, jan)
SELECT p.id, 'FT1196-0306-100', c.id, s.id, '100', '4900000000011'
  FROM products p, colors c, sizes s WHERE p.product_code='FT1196' AND c.code='03' AND s.code='06';
INSERT INTO skus (product_id, sku_code, color_id, size_id, pack_division, jan)
SELECT p.id, 'FT1198-0204-100', c.id, s.id, '100', '4900000000028'
  FROM products p, colors c, sizes s WHERE p.product_code='FT1198' AND c.code='02' AND s.code='04';
INSERT INTO skus (product_id, sku_code, pack_division)
SELECT p.id, 'FT1198-11606-200', '200' FROM products p WHERE p.product_code='FT1198-1';
INSERT INTO skus (product_id, sku_code, pack_division)
SELECT p.id, 'CS2420-0000-100', '100' FROM products p WHERE p.product_code='CS2420';

-- セット構成：2枚組 ＝ FT1198 単品 × 2
INSERT INTO set_headers (sku_id) SELECT id FROM skus WHERE sku_code='FT1198-11606-200';
INSERT INTO set_components (set_header_id, component_sku_id, qty)
SELECT h.id, s.id, 2 FROM set_headers h, skus s
 WHERE h.sku_id=(SELECT id FROM skus WHERE sku_code='FT1198-11606-200')
   AND s.sku_code='FT1198-0204-100';

-- 取引先別商品（Amazon 専用コードの読み替え）
INSERT INTO partner_products (partner_id, sku_id, partner_product_code, sales_name, unit_price)
SELECT p.id, s.id, 'TO-GXZN-60W8', 'LUXCEAR Fornez PRO（Amazon）', 7255
  FROM partners p, skus s WHERE p.partner_code='AMZN' AND s.sku_code='CS2420-0000-100';
INSERT INTO partner_products (partner_id, sku_id, partner_product_code, sales_name, unit_price)
SELECT p.id, s.id, 'CL-A-001', '販社向け商品名', 3500
  FROM partners p, skus s WHERE p.partner_code='P001' AND s.sku_code='FT1196-0306-100';

-- 在庫（良品 100個）
INSERT INTO stocks (sku_id, warehouse_id, quality_code_id, qty_on_hand)
SELECT s.id, w.id, q.id, 100
  FROM skus s, warehouses w,
       (SELECT c.id FROM codes c JOIN code_categories cc ON cc.id=c.code_category_id
         WHERE cc.code='QUALITY_DIVISION' AND c.code='GOOD') q
 WHERE s.sku_code='FT1196-0306-100' AND w.warehouse_code='0001';
INSERT INTO stocks (sku_id, warehouse_id, quality_code_id, qty_on_hand)
SELECT s.id, w.id, q.id, 50
  FROM skus s, warehouses w,
       (SELECT c.id FROM codes c JOIN code_categories cc ON cc.id=c.code_category_id
         WHERE cc.code='QUALITY_DIVISION' AND c.code='GOOD') q
 WHERE s.sku_code='FT1198-0204-100' AND w.warehouse_code='0001';

-- ----------------------------------------------------------------------------
-- T05  有効在庫の生成列
-- ----------------------------------------------------------------------------
DO $$
DECLARE av numeric;
BEGIN
  UPDATE stocks SET qty_allocated = 30
   WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1196-0306-100');
  SELECT qty_available INTO av FROM stocks
   WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1196-0306-100');
  IF av <> 70 THEN
    RAISE EXCEPTION 'T05 失敗: 有効在庫が %（期待 70）', av USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T05 OK  有効在庫＝実在庫−引当済（100−30＝70）';
  UPDATE stocks SET qty_allocated = 0
   WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1196-0306-100');
END $$;

-- ----------------------------------------------------------------------------
-- T06〜T08  在庫の整合性制約
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    UPDATE stocks SET qty_allocated = 999
     WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1196-0306-100');
    RAISE EXCEPTION 'T06 失敗: 引当済＞実在庫が通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T06 OK  引当済＞実在庫を拒否';
  END;

  BEGIN
    UPDATE stocks SET qty_on_hand = -1
     WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1196-0306-100');
    RAISE EXCEPTION 'T07 失敗: 実在庫の負数が通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T07 OK  実在庫の負数を拒否';
  END;

  BEGIN
    INSERT INTO stocks (sku_id, warehouse_id, quality_code_id, qty_on_hand)
    SELECT s.id, w.id, q.id, 10
      FROM skus s, warehouses w,
           (SELECT c.id FROM codes c JOIN code_categories cc ON cc.id=c.code_category_id
             WHERE cc.code='QUALITY_DIVISION' AND c.code='GOOD') q
     WHERE s.sku_code='FT1196-0306-100' AND w.warehouse_code='0001';
    RAISE EXCEPTION 'T08 失敗: 在庫の重複行が作れてしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'T08 OK  (SKU×倉庫×ロット×品質区分) の一意性';
  END;
END $$;

-- ----------------------------------------------------------------------------
-- T09  引当 → 引当解除で有効在庫が戻り、実在庫は不変
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_order_id bigint; v_line_id bigint; v_stock_id bigint; v_alloc_id bigint;
  on_hand0 numeric; avail0 numeric; on_hand1 numeric; avail1 numeric;
  on_hand2 numeric; avail2 numeric;
BEGIN
  SELECT id, qty_on_hand, qty_available INTO v_stock_id, on_hand0, avail0
    FROM stocks WHERE sku_id=(SELECT id FROM skus WHERE sku_code='FT1196-0306-100');

  INSERT INTO sales_orders (order_no, order_type, partner_id, delivery_destination_id,
                            sales_category_id, order_date, status)
  SELECT 'SO-TEST-001', '卸', p.id, d.id, sc.id, CURRENT_DATE, '未確定'
    FROM partners p, delivery_destinations d, sales_categories sc
   WHERE p.partner_code='P001' AND d.delivery_code='D001' AND sc.code='OA'
  RETURNING id INTO v_order_id;

  INSERT INTO sales_order_lines (sales_order_id, line_no, line_type, sku_id, item_name, qty, unit_price, tax_rate, amount)
  SELECT v_order_id, 1, '商品', s.id, '販社向け商品名', 20, 3500, 10.00, 70000
    FROM skus s WHERE s.sku_code='FT1196-0306-100'
  RETURNING id INTO v_line_id;

  -- 引当
  UPDATE stocks SET qty_allocated = qty_allocated + 20 WHERE id = v_stock_id;
  INSERT INTO allocations (sales_order_line_id, stock_id, sku_id, qty, status)
  SELECT v_line_id, v_stock_id, s.id, 20, '引当中' FROM skus s WHERE s.sku_code='FT1196-0306-100'
  RETURNING id INTO v_alloc_id;
  INSERT INTO stock_movements (stock_id, movement_type, ref_table, ref_id, qty, qty_before, qty_after)
  VALUES (v_stock_id, '引当', 'sales_order_lines', v_line_id, 20, avail0, avail0 - 20);

  SELECT qty_on_hand, qty_available INTO on_hand1, avail1 FROM stocks WHERE id = v_stock_id;
  IF on_hand1 <> on_hand0 THEN
    RAISE EXCEPTION 'T09 失敗: 引当で実在庫が変動した（% → %）', on_hand0, on_hand1 USING ERRCODE='TF001';
  END IF;
  IF avail1 <> avail0 - 20 THEN
    RAISE EXCEPTION 'T09 失敗: 引当後の有効在庫が %（期待 %）', avail1, avail0-20 USING ERRCODE='TF001';
  END IF;

  -- 引当解除（出荷一覧からの削除）
  UPDATE allocations SET status='解除', released_at=now() WHERE id = v_alloc_id;
  UPDATE stocks SET qty_allocated = qty_allocated - 20 WHERE id = v_stock_id;
  INSERT INTO stock_movements (stock_id, movement_type, ref_table, ref_id, qty, qty_before, qty_after)
  VALUES (v_stock_id, '引当解除', 'sales_order_lines', v_line_id, -20, avail1, avail1 + 20);

  SELECT qty_on_hand, qty_available INTO on_hand2, avail2 FROM stocks WHERE id = v_stock_id;
  IF on_hand2 <> on_hand0 THEN
    RAISE EXCEPTION 'T09 失敗: 引当解除で実在庫が変動した' USING ERRCODE='TF001';
  END IF;
  IF avail2 <> avail0 THEN
    RAISE EXCEPTION 'T09 失敗: 引当解除後の有効在庫が %（期待 %）', avail2, avail0 USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T09 OK  引当解除で有効在庫が戻り、実在庫は不変（実在庫 % のまま）', on_hand0;
END $$;

-- ----------------------------------------------------------------------------
-- T10  セット商品は在庫を持たず、構成商品から引き落とす
-- ----------------------------------------------------------------------------
DO $$
DECLARE n int; comp_avail numeric;
BEGIN
  SELECT count(*) INTO n FROM stocks st
    JOIN skus s ON s.id = st.sku_id JOIN products p ON p.id = s.product_id
   WHERE p.is_set = true;
  IF n <> 0 THEN
    RAISE EXCEPTION 'T10 失敗: セット商品に在庫行が % 件存在する', n USING ERRCODE='TF001';
  END IF;

  -- セット2個の受注 → 構成品を 2×2＝4 個引き当てる
  SELECT sc.component_sku_id, 0 INTO n, comp_avail
    FROM set_components sc JOIN set_headers h ON h.id = sc.set_header_id
    JOIN skus s ON s.id = h.sku_id WHERE s.sku_code='FT1198-11606-200';

  UPDATE stocks SET qty_allocated = qty_allocated + 4
   WHERE sku_id = (SELECT sc.component_sku_id FROM set_components sc
                     JOIN set_headers h ON h.id = sc.set_header_id
                     JOIN skus s ON s.id = h.sku_id
                    WHERE s.sku_code='FT1198-11606-200');
  SELECT qty_available INTO comp_avail FROM stocks
   WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1198-0204-100');
  IF comp_avail <> 46 THEN
    RAISE EXCEPTION 'T10 失敗: 構成品の有効在庫が %（期待 46）', comp_avail USING ERRCODE='TF001';
  END IF;
  UPDATE stocks SET qty_allocated = 0
   WHERE sku_id = (SELECT id FROM skus WHERE sku_code='FT1198-0204-100');
  RAISE NOTICE 'T10 OK  セットは在庫を持たず、構成品から引き落とし（50−4＝46）';
END $$;

-- ----------------------------------------------------------------------------
-- T11〜T13  受注の業務ルール
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_order_id bigint;
BEGIN
  BEGIN
    INSERT INTO sales_orders (order_no, order_type, partner_id, sales_category_id, order_date)
    SELECT 'SO-TEST-NG', '卸', p.id, sc.id, CURRENT_DATE
      FROM partners p, sales_categories sc WHERE p.partner_code='P001' AND sc.code='OA';
    RAISE EXCEPTION 'T11 失敗: 卸受注で納品先なしが通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T11 OK  卸受注は納品先が必須';
  END;

  -- 通販受注（直送）：個人宛のみ、納品先なしで登録できる
  INSERT INTO sales_orders (order_no, order_type, partner_id, sales_category_id, order_date,
                            direct_name, direct_postal_code, direct_address1, channel)
  SELECT 'SO-TEST-002', '通販', p.id, sc.id, CURRENT_DATE,
         'テスト 太郎', '1000001', '東京都千代田区', '自社サイト'
    FROM partners p, sales_categories sc WHERE p.partner_code='P001' AND sc.code='WEB'
  RETURNING id INTO v_order_id;

  -- 商品行
  INSERT INTO sales_order_lines (sales_order_id, line_no, line_type, sku_id, item_name, qty, unit_price, tax_rate, amount)
  SELECT v_order_id, 1, '商品', s.id, '滑らかシームレスエアーHOT', 1, 7255, 10.00, 7255
    FROM skus s WHERE s.sku_code='FT1196-0306-100';

  -- 販促品行（個数 −1）
  INSERT INTO sales_order_lines (sales_order_id, line_no, line_type, sku_id, item_name, qty, unit_price, tax_rate, amount)
  SELECT v_order_id, 2, '販促品', s.id, '2026年夏の粗品特別値引', -1, 0, 10.00, 0
    FROM skus s WHERE s.sku_code='FT1196-0306-100';

  -- 送料行（sku_id なし）
  INSERT INTO sales_order_lines (sales_order_id, line_no, line_type, item_name, qty, unit_price, tax_rate, amount)
  VALUES (v_order_id, 3, '送料', '送料', 1, 500, 10.00, 500);

  -- 値引行（sku_id なし・負数）
  INSERT INTO sales_order_lines (sales_order_id, line_no, line_type, item_name, qty, unit_price, tax_rate, amount)
  VALUES (v_order_id, 4, '値引', 'クーポン分(店舗発行)：500円OFF', -1, 500, 10.00, -500);
  RAISE NOTICE 'T12 OK  販促品（数量 −1）・送料行・値引行を登録できる';

  BEGIN
    INSERT INTO sales_order_lines (sales_order_id, line_no, line_type, item_name, qty, unit_price, tax_rate, amount)
    VALUES (v_order_id, 5, '商品', 'SKUなし商品行', 1, 100, 10.00, 100);
    RAISE EXCEPTION 'T13 失敗: 商品行で SKU なしが通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T13 OK  商品行は SKU 必須／送料・値引行は SKU 不要';
  END;
END $$;

-- ----------------------------------------------------------------------------
-- T14  CSV 取込の冪等性
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_batch bigint;
BEGIN
  INSERT INTO import_batches (import_type, file_name, total_count, success_count)
  VALUES ('OMS_ORDER', 'OS_beautyjapan_20260901_170556.csv', 1, 1) RETURNING id INTO v_batch;

  INSERT INTO external_orders (import_batch_id, channel, external_order_no, raw_data)
  VALUES (v_batch, '自社サイト', 'JSb2472e28e8', '{"受注番号":"JSb2472e28e8"}'::jsonb);

  BEGIN
    INSERT INTO external_orders (import_batch_id, channel, external_order_no, raw_data)
    VALUES (v_batch, '自社サイト', 'JSb2472e28e8', '{"受注番号":"JSb2472e28e8"}'::jsonb);
    RAISE EXCEPTION 'T14 失敗: 同一受注番号の二重取込が通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'T14 OK  (チャネル×外部受注番号) の二重取込を拒否';
  END;

  -- 別チャネルの同一番号は登録できる
  INSERT INTO external_orders (import_batch_id, channel, external_order_no, raw_data)
  VALUES (v_batch, '楽天通常購入', 'JSb2472e28e8', '{}'::jsonb);
  RAISE NOTICE 'T14b OK  チャネルが異なれば同一番号を登録できる';
END $$;

-- ----------------------------------------------------------------------------
-- T15〜T16  取引先専用コードの一意性
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    INSERT INTO partner_products (partner_id, sku_id, partner_product_code, unit_price)
    SELECT p.id, s.id, 'TO-GXZN-60W8', 1
      FROM partners p, skus s WHERE p.partner_code='AMZN' AND s.sku_code='FT1196-0306-100';
    RAISE EXCEPTION 'T15 失敗: 同一取引先で専用コードが重複できてしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'T15 OK  (取引先×専用コード) の一意性';
  END;

  INSERT INTO partner_products (partner_id, sku_id, unit_price)
  SELECT p.id, s.id, 1 FROM partners p, skus s
   WHERE p.partner_code='S001' AND s.sku_code='FT1196-0306-100';
  INSERT INTO partner_products (partner_id, sku_id, unit_price)
  SELECT p.id, s.id, 1 FROM partners p, skus s
   WHERE p.partner_code='S001' AND s.sku_code='FT1198-0204-100';
  RAISE NOTICE 'T16 OK  専用コード未設定（NULL）は同一取引先で複数登録できる';
END $$;

-- ----------------------------------------------------------------------------
-- T17  Amazon SKU → 自社 SKU の読み替え
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_sku text;
BEGIN
  SELECT s.sku_code INTO v_sku
    FROM partner_products pp
    JOIN partners p ON p.id = pp.partner_id
    JOIN skus s     ON s.id = pp.sku_id
   WHERE p.partner_code = 'AMZN' AND pp.partner_product_code = 'TO-GXZN-60W8';
  IF v_sku IS DISTINCT FROM 'CS2420-0000-100' THEN
    RAISE EXCEPTION 'T17 失敗: Amazon SKU の読み替え結果が %（期待 CS2420-0000-100）', v_sku USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T17 OK  Amazon SKU「TO-GXZN-60W8」→ 自社 SKU「%」', v_sku;
END $$;

-- ----------------------------------------------------------------------------
-- T18〜T19  追記専用テーブル
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    UPDATE stock_movements SET qty = 0 WHERE id = (SELECT min(id) FROM stock_movements);
    RAISE EXCEPTION 'T18 失敗: 在庫移動履歴を更新できてしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'T18 OK  在庫移動履歴の UPDATE を拒否';
  END;

  BEGIN
    DELETE FROM stock_movements WHERE id = (SELECT min(id) FROM stock_movements);
    RAISE EXCEPTION 'T19 失敗: 在庫移動履歴を削除できてしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'T19 OK  在庫移動履歴の DELETE を拒否';
  END;
END $$;

-- ----------------------------------------------------------------------------
-- T20〜T23  その他の業務制約
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_inv bigint; t0 timestamptz; t1 timestamptz;
BEGIN
  INSERT INTO invoices (invoice_no, partner_id, closing_date, period_from, period_to)
  SELECT 'IV-TEST-001', p.id, DATE '2026-08-31', DATE '2026-08-01', DATE '2026-08-31'
    FROM partners p WHERE p.partner_code='P001' RETURNING id INTO v_inv;
  BEGIN
    INSERT INTO invoices (invoice_no, partner_id, closing_date, period_from, period_to)
    SELECT 'IV-TEST-002', p.id, DATE '2026-08-31', DATE '2026-08-01', DATE '2026-08-31'
      FROM partners p WHERE p.partner_code='P001';
    RAISE EXCEPTION 'T20 失敗: 同一締め期間の二重請求が通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'T20 OK  (取引先×締め期間) の二重請求を拒否';
  END;

  BEGIN
    INSERT INTO reservations (partner_id, sales_category_id, sku_id, period_from, period_to, reserved_qty)
    SELECT p.id, sc.id, s.id, DATE '2026-09-30', DATE '2026-09-01', 10
      FROM partners p, sales_categories sc, skus s
     WHERE p.partner_code='P001' AND sc.code='OA' AND s.sku_code='FT1196-0306-100';
    RAISE EXCEPTION 'T21 失敗: 確保数の期間が逆転しても通ってしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T21 OK  確保数の期間逆転を拒否';
  END;

  BEGIN
    INSERT INTO partners (partner_code, name1, is_customer, is_supplier)
    VALUES ('P999', '役割なし取引先', false, false);
    RAISE EXCEPTION 'T22 失敗: 得意先でも仕入先でもない取引先が作れてしまった' USING ERRCODE='TF001';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'T22 OK  得意先／仕入先のいずれでもない取引先を拒否';
  END;

  SELECT updated_at INTO t0 FROM partners WHERE partner_code='P001';
  PERFORM pg_sleep(0.05);
  UPDATE partners SET short_name='更新テスト' WHERE partner_code='P001';
  SELECT updated_at INTO t1 FROM partners WHERE partner_code='P001';
  IF t1 <= t0 THEN
    RAISE EXCEPTION 'T23 失敗: updated_at が更新されていない' USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T23 OK  updated_at トリガが動作';
END $$;

-- ----------------------------------------------------------------------------
-- T24  同梱（出荷の自己参照）
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_parent bigint; v_child bigint;
BEGIN
  INSERT INTO shipments (shipment_no, warehouse_id, status)
  SELECT 'D0209475', w.id, '確定済' FROM warehouses w WHERE w.warehouse_code='0001'
  RETURNING id INTO v_parent;
  INSERT INTO shipments (shipment_no, warehouse_id, status, consolidated_to_shipment_id)
  SELECT 'D0209476', w.id, '確定済', v_parent FROM warehouses w WHERE w.warehouse_code='0001'
  RETURNING id INTO v_child;
  IF (SELECT consolidated_to_shipment_id FROM shipments WHERE id=v_child) <> v_parent THEN
    RAISE EXCEPTION 'T24 失敗: 同梱先の参照が張れていない' USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T24 OK  同梱（複数出荷を1つにまとめる自己参照）';
END $$;

-- ----------------------------------------------------------------------------
-- T25  外部キーの網羅性（孤立参照が存在しないこと）
-- ----------------------------------------------------------------------------
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_constraint c
    JOIN pg_class t  ON t.oid = c.conrelid
    JOIN pg_namespace ns ON ns.oid = t.relnamespace
   WHERE ns.nspname='cony' AND c.contype='f';
  IF n < 90 THEN
    RAISE EXCEPTION 'T25 失敗: 外部キーが % 件しかない（90 件以上を期待）', n USING ERRCODE='TF001';
  END IF;
  RAISE NOTICE 'T25 OK  外部キー % 件', n;

  SELECT count(*) INTO n FROM pg_constraint c
    JOIN pg_class t  ON t.oid = c.conrelid
    JOIN pg_namespace ns ON ns.oid = t.relnamespace
   WHERE ns.nspname='cony' AND c.contype='c';
  RAISE NOTICE 'T26 OK  CHECK 制約 % 件', n;

  SELECT count(*) INTO n FROM pg_indexes WHERE schemaname='cony';
  RAISE NOTICE 'T27 OK  インデックス % 件', n;
END $$;

-- ----------------------------------------------------------------------------
-- 完了
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '==================================================';
  RAISE NOTICE '  スキーマ受入テスト 全件合格';
  RAISE NOTICE '==================================================';
END $$;
