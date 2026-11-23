-- =============================================
-- MARKETING CAMPAIGN PERFORMANCE ANALYSIS
-- Author: Merdi Mayindu
-- Tool: SQLite (DB Browser)
-- Data: iFood marketing campaign dataset (Kaggle), table = marketing
-- =============================================

-- ---------- PHASE 1: DATA CHECKS ----------

-- 1. How many customers are there, and are there any duplicates?
-- Finding: 2,240 rows and 2,240 unique customer IDs,
-- so each row is one customer and there are no duplicates.
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT ID) AS unique_customers
FROM marketing;

-- 2. Are there any missing income values?
-- Finding: 24 customers have no income recorded (about 1% of the data).
-- They are kept in the data but left out of income-based analysis.
SELECT COUNT(*) AS missing_income
FROM marketing
WHERE Income IS NULL OR TRIM(Income) = '';

-- 3. What format is Income stored in?
-- Finding: Income is stored as text with a dollar sign, commas and a trailing
-- space (e.g. '$84,835.00 '), so it can't be used in calculations yet.
-- Fix: strip the symbols and convert it to a number in the clean view.
SELECT ID, Income
FROM marketing
LIMIT 5;

-- 4. Are there any unrealistic birth years?
-- Finding: 3 customers have birth years of 1893, 1899 and 1900, which would make
-- them over 110 years old. These are data entry errors, so they are
-- removed in the clean view.
SELECT ID, Year_Birth
FROM marketing
WHERE Year_Birth < 1940
ORDER BY Year_Birth;

-- 5. Are there any unusual marital status values?
-- Finding: Most customers are Married, Together, Single, Divorced or Widow, but
-- 7 have invalid values ('Alone', 'YOLO', 'Absurd'). Fix: group everyone into
-- 'Couple' (Married/Together) or 'Single' (everyone else) in the clean view.
SELECT Marital_Status, COUNT(*) AS customers
FROM marketing
GROUP BY Marital_Status
ORDER BY customers DESC;

-- ---------- PHASE 2: DATA CLEANING ----------

-- 6. Create a clean view of the data for analysis
-- Finding: Converted Income to a number, removed the 3 impossible birth years
-- (2,237 customers remain), and added age, relationship, number of children,
-- total spend, total purchases and number of previous campaigns accepted.
DROP VIEW IF EXISTS marketing_clean;
CREATE VIEW marketing_clean AS
SELECT *,
  CASE WHEN Income IS NULL OR TRIM(Income) = '' THEN NULL
       ELSE CAST(REPLACE(REPLACE(TRIM(Income), '$', ''), ',', '') AS REAL)
  END AS income_num,
  2014 - Year_Birth AS age,
  CASE WHEN Marital_Status IN ('Married', 'Together') THEN 'Couple'
       ELSE 'Single' END AS relationship,
  Kidhome + Teenhome AS children,
  MntWines + MntFruits + MntMeatProducts + MntFishProducts
    + MntSweetProducts + MntGoldProds AS total_spend,
  NumWebPurchases + NumCatalogPurchases + NumStorePurchases AS total_purchases,
  AcceptedCmp1 + AcceptedCmp2 + AcceptedCmp3 + AcceptedCmp4 + AcceptedCmp5 AS prev_accepted
FROM marketing
WHERE Year_Birth >= 1940;

-- ---------- PHASE 3: CAMPAIGN ANALYSIS ----------

-- 7. What was the acceptance rate of each campaign?
-- Finding: The latest campaign had a 14.9% response rate, double the best of the
-- previous five (6.4% to 7.5%). Campaign 2 performed worst at just 1.3%.
SELECT 'Campaign 1' AS campaign, ROUND(100.0 * AVG(AcceptedCmp1), 1) AS acceptance_rate_pct FROM marketing_clean
UNION ALL SELECT 'Campaign 2', ROUND(100.0 * AVG(AcceptedCmp2), 1) FROM marketing_clean
UNION ALL SELECT 'Campaign 3', ROUND(100.0 * AVG(AcceptedCmp3), 1) FROM marketing_clean
UNION ALL SELECT 'Campaign 4', ROUND(100.0 * AVG(AcceptedCmp4), 1) FROM marketing_clean
UNION ALL SELECT 'Campaign 5', ROUND(100.0 * AVG(AcceptedCmp5), 1) FROM marketing_clean
UNION ALL SELECT 'Latest campaign', ROUND(100.0 * AVG(Response), 1) FROM marketing_clean;

-- 8. Do customers who accepted earlier campaigns respond more to the latest one?
-- Finding: This is the strongest predictor of response. Customers who accepted no
-- previous campaigns responded at 8.2%. That rises to 31.2% after one
-- acceptance, 50.6% after two and 79.5% after three. Customers who accepted at
-- least one earlier campaign are 21% of customers but 56% of responders.
SELECT prev_accepted AS previous_campaigns_accepted,
  COUNT(*) AS customers,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct
FROM marketing_clean
GROUP BY prev_accepted
ORDER BY prev_accepted;

-- 9. Response rate by country
-- Finding: Response rates are similar across most countries (14-16%). Spain is the
-- biggest market (1,094 customers) and responds best at 16.1%. India responds
-- lowest at 8.8%. Mexico (3 customers) was excluded as the sample is too small.
SELECT Country,
  COUNT(*) AS customers,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct
FROM marketing_clean
GROUP BY Country
HAVING COUNT(*) >= 50
ORDER BY response_rate_pct DESC;

-- 10. Response rate by income band
-- Finding: Customers earning 70k+ respond at 28.0%, more than double every other
-- income band (10-12%). They also spend the most, averaging 1,376 each.
SELECT CASE
    WHEN income_num < 30000 THEN '1. Under 30k'
    WHEN income_num < 50000 THEN '2. 30k-50k'
    WHEN income_num < 70000 THEN '3. 50k-70k'
    ELSE '4. 70k+'
  END AS income_band,
  COUNT(*) AS customers,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct,
  ROUND(AVG(total_spend), 0) AS avg_spend
FROM marketing_clean
WHERE income_num IS NOT NULL
GROUP BY income_band
ORDER BY income_band;

-- 11. Do customers with children respond differently?
-- Finding: Customers with no children respond at 26.5% vs 10.3% for those with
-- children, and spend almost 3x more on average (1,105 vs 407).
SELECT CASE WHEN children = 0 THEN 'No children' ELSE 'Has children' END AS household,
  COUNT(*) AS customers,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct,
  ROUND(AVG(total_spend), 0) AS avg_spend
FROM marketing_clean
GROUP BY household
ORDER BY response_rate_pct DESC;

-- 12. Response rate by relationship status
-- Finding: Single customers respond at 22.2%, double the rate of couples (10.9%).
SELECT relationship,
  COUNT(*) AS customers,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct
FROM marketing_clean
GROUP BY relationship
ORDER BY response_rate_pct DESC;

-- 13. How does time since last purchase (recency) affect response?
-- Finding: Recent customers respond best. Those who bought in the last 30 days
-- respond at 23.9%, falling to 8.4% for customers who haven't bought in 60+ days.
SELECT CASE
    WHEN Recency <= 30 THEN '1. 0-30 days'
    WHEN Recency <= 60 THEN '2. 31-60 days'
    ELSE '3. 61+ days'
  END AS recency_band,
  COUNT(*) AS customers,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct
FROM marketing_clean
GROUP BY recency_band
ORDER BY recency_band;

-- 14. Do responders spend more than non-responders?
-- Finding: Responders spend 987 on average vs 539 for non-responders (83% more),
-- and earn around 9,400 more per year. The campaign appeals to high-value customers.
SELECT CASE WHEN Response = 1 THEN 'Responded' ELSE 'Did not respond' END AS group_name,
  COUNT(*) AS customers,
  ROUND(AVG(total_spend), 0) AS avg_spend,
  ROUND(AVG(income_num), 0) AS avg_income
FROM marketing_clean
GROUP BY group_name;

-- ---------- PHASE 4: SALES & CHANNEL ANALYSIS ----------

-- 15. Which product categories bring in the most revenue?
-- Finding: Wine (50.2%) and meat (27.6%) make up over three-quarters of all revenue.
-- Every other category is under 8%.
SELECT 'Wine' AS category, SUM(MntWines) AS revenue,
  ROUND(100.0 * SUM(MntWines) / SUM(total_spend), 1) AS pct_of_revenue FROM marketing_clean
UNION ALL SELECT 'Meat', SUM(MntMeatProducts), ROUND(100.0 * SUM(MntMeatProducts) / SUM(total_spend), 1) FROM marketing_clean
UNION ALL SELECT 'Gold', SUM(MntGoldProds), ROUND(100.0 * SUM(MntGoldProds) / SUM(total_spend), 1) FROM marketing_clean
UNION ALL SELECT 'Fish', SUM(MntFishProducts), ROUND(100.0 * SUM(MntFishProducts) / SUM(total_spend), 1) FROM marketing_clean
UNION ALL SELECT 'Sweets', SUM(MntSweetProducts), ROUND(100.0 * SUM(MntSweetProducts) / SUM(total_spend), 1) FROM marketing_clean
UNION ALL SELECT 'Fruits', SUM(MntFruits), ROUND(100.0 * SUM(MntFruits) / SUM(total_spend), 1) FROM marketing_clean
ORDER BY revenue DESC;

-- 16. Which purchase channel do customers use most?
-- Finding: The store is the main channel (46.2% of purchases), followed by web
-- (32.6%) and catalog (21.2%).
SELECT 'Store' AS channel, SUM(NumStorePurchases) AS purchases,
  ROUND(100.0 * SUM(NumStorePurchases) / SUM(total_purchases), 1) AS pct_of_purchases FROM marketing_clean
UNION ALL SELECT 'Web', SUM(NumWebPurchases), ROUND(100.0 * SUM(NumWebPurchases) / SUM(total_purchases), 1) FROM marketing_clean
UNION ALL SELECT 'Catalog', SUM(NumCatalogPurchases), ROUND(100.0 * SUM(NumCatalogPurchases) / SUM(total_purchases), 1) FROM marketing_clean
ORDER BY purchases DESC;

-- 17. Best target segment: accepted a previous campaign + no children
-- Finding: 230 customers have accepted a previous campaign and have no children.
-- They respond at 50.0%, over 3x the 14.9% average. This group is about 10%
-- of customers but produced 34% of all responses (115 of 334).
SELECT COUNT(*) AS customers,
  SUM(Response) AS responders,
  ROUND(100.0 * AVG(Response), 1) AS response_rate_pct
FROM marketing_clean
WHERE prev_accepted >= 1
  AND children = 0;
  
-- 18. Create a dashboard view for Power BI
-- Finding: Adds income band, household and recency band columns so the
-- dashboard can group customers without extra work in Power BI.
DROP VIEW IF EXISTS dashboard_data;
CREATE VIEW dashboard_data AS
SELECT ID, Country, Response, total_spend, income_num, prev_accepted, relationship,
  CASE WHEN income_num IS NULL THEN 'Unknown'
       WHEN income_num < 30000 THEN '1. Under 30k'
       WHEN income_num < 50000 THEN '2. 30k-50k'
       WHEN income_num < 70000 THEN '3. 50k-70k'
       ELSE '4. 70k+' END AS income_band,
  CASE WHEN children = 0 THEN 'No children' ELSE 'Has children' END AS household,
  CASE WHEN Recency <= 30 THEN '1. 0-30 days'
       WHEN Recency <= 60 THEN '2. 31-60 days'
       ELSE '3. 61+ days' END AS recency_band
FROM marketing_clean;

-- ---------- SUMMARY & RECOMMENDATIONS ----------
-- 1. Target past responders first. Customers who accepted an earlier campaign
--    are 3-10x more likely to respond, so they should get every new campaign.
-- 2. Focus spend on the highest-value segment: high income (70k+), no children,
--    single customers. They respond most and spend the most.
-- 3. Time campaigns around recent activity. Contact customers within 30 days
--    of their last purchase, and build a separate win-back offer for those
--    inactive for 60+ days.
-- 4. Lead with wine and meat offers, which drive over 75% of revenue, and keep
--    in-store promotion strong since the store is the main channel.
-- 5. Don't repeat Campaign 2's approach. At 1.3% it was the clear worst performer.
