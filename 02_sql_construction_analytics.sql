--2. Project Budget vs. Actuals Analysis (Query #2)
--Business Question: Are our projects on, over, or under budget? 
--Which projects have the largest financial variance, both in absolute and percentage terms?
--Description: This is a critical financial health check. 
--The query joins project budget information with actual cost data, calculating the variance in both absolute currency and as a percentage. 
--It uses a LEFT JOIN to ensure all projects are included in the report, even those with no costs yet. 
--The results are sorted to immediately highlight the projects with the most significant budget overruns.

SELECT
  p.project_name,
  p.budget_eur,
  COALESCE(SUM(c.amount_eur), 0) AS total_cost,
  ROUND(COALESCE(SUM(c.amount_eur), 0) - COALESCE(p.budget_eur, 0), 2) AS variance_eur,
  ROUND(
    100.0 * (COALESCE(SUM(c.amount_eur), 0) - COALESCE(p.budget_eur, 0))
    / NULLIF(p.budget_eur, 0), 2
  ) AS variance_pct
FROM construction.projects p
LEFT JOIN construction.costs c ON c.project_id = p.project_id
GROUP BY p.project_id, p.project_name, p.budget_eur
ORDER BY variance_pct DESC NULLS LAST;

--4. Monthly Cost Trend (Query #2 from the second group)
--Business Question: How are our total project costs evolving over time? 
--Are there seasonal patterns or specific months with unusually high expenses?
--Description: This query aggregates all project costs on a monthly basis to provide a 
--high-level view of the overall spending trend. It uses the date_trunc function to group daily costs 
--into monthly totals, which is essential for identifying patterns and forecasting future expenses.

SELECT
  date_trunc('MONTH', c.date)::DATE AS month,
  SUM(c.amount_eur)           AS total_cost
FROM construction.costs c
GROUP BY 1
ORDER BY 1;

--7. Cost Breakdown by Type (Query #5 from the second group)
--Business Question: Where is our money going? 
--What are the primary categories of our expenses (e.g., materials, workforce, machinery)?
--Description: This query provides a simple but powerful breakdown of total costs by their type. 
--By grouping all expenditures into categories, it helps identify the main cost drivers across 
--all projects, answering the fundamental question of where resources are being allocated.

SELECT
  c.cost_type,
  SUM(c.amount_eur) AS total_cost
FROM construction.costs c
GROUP BY c.cost_type
ORDER BY total_cost DESC;

--1. Cost Breakdown by Phase (Query #1)
--Business Question: Which phases of the construction process are the most expensive? 
--What is the percentage contribution of each phase to the total cost?
--Description: This query drills down into the cost structure by construction phase (e.g., foundations, structural work, finishing). 
--It uses a Common Table Expression (CTE) to first calculate the total cost per phase, 
--and then a Window Function (SUM() OVER()) to calculate each phase's percentage share of the grand total, 
--providing crucial insights for future project planning and budgeting.

WITH phase_costs AS (
  SELECT
    ph.phase_name,
    COALESCE (SUM (c.amount_eur), 0) AS total_cost
  FROM construction.costs c
  JOIN construction.phases ph ON ph.phase_id = c.phase_id
  GROUP BY ph.phase_name
)
SELECT
  phase_name,
  total_cost,
  ROUND(100.0 * total_cost / NULLIF(SUM(total_cost) OVER (), 0), 2) AS pct_of_total
FROM phase_costs
ORDER BY total_cost DESC;

--3. Top 10 Materials by Purchase Spend (Query #1 from the second group)
--Business Question: Which specific materials are driving our material costs? 
--Where should we focus our procurement and negotiation efforts?
--Description: This query identifies the top 10 most expensive materials 
--by calculating the total spend for each (quantity multiplied by unit price).
--This analysis is vital for supply chain management, 
--helping to pinpoint key materials where cost-saving initiatives or better vendor negotiations could have the most significant impact.

SELECT
  m.material_name,
  SUM(p.quantity) AS total_qty,
  ROUND(SUM(p.quantity * m.unit_price_eur), 2) AS total_spend_eur
FROM construction.purchases p
JOIN construction.materials  m ON m.material_id = p.material_id
GROUP BY m.material_name
ORDER BY total_spend_eur DESC
LIMIT 10;

--5. Net Stock by Material (Query #3 from the second group)
--Business Question: How well are we managing our material inventory? 
--Do we have a surplus or a deficit of key materials on-site?
--Description: This query calculates the net stock quantity 
--for each material by comparing total purchases against total consumption. 
--It cleverly uses a CTE with a UNION ALL to first aggregate purchase and consumption data into a unified list, 
--then performs the final calculation. 
--This is essential for logistics, preventing work stoppages due to material shortages and reducing waste from over-purchasing.

WITH x AS (
  SELECT material_id, SUM(quantity) AS purch_qty, 0 AS cons_qty
  FROM construction.purchases
  GROUP BY material_id
  UNION ALL
  SELECT material_id, 0, SUM(quantity)
  FROM construction.consumption
  GROUP BY material_id
)
SELECT
  m.material_name,
  SUM(x.purch_qty) AS purch_qty,
  SUM(x.cons_qty)  AS cons_qty,
  SUM(x.purch_qty - x.cons_qty) AS stock_qty
FROM x
JOIN construction.materials m USING (material_id)
GROUP BY m.material_name
ORDER BY stock_qty DESC;

--6.Delays Summary per Project (Query #4 from the second group)
--Business Question: Which projects are falling behind schedule? 
--What is the total and average delay, and how widespread is the problem within each project?
--Description: This query provides a comprehensive summary of project delays. 
--It calculates three key metrics for each project: 
--the total number of delay days (using GREATEST to ignore phases finished ahead of schedule), 
--the average delay per phase, and the total count of phases that were late. 
--This multi-faceted view helps managers distinguish between projects with a single major delay and those with systemic scheduling issues.

SELECT
  pr.project_name,
  SUM(GREATEST(k.delay_days, 0))                     AS total_delay_days,
  ROUND(AVG(k.delay_days)::numeric, 2)               AS avg_delay_days,
  SUM(CASE WHEN k.delay_days > 0 THEN 1 ELSE 0 END)  AS late_phases
FROM construction.phase_delays k
JOIN construction.projects pr ON pr.project_id = k.project_id
GROUP BY pr.project_name
ORDER BY total_delay_days DESC;

