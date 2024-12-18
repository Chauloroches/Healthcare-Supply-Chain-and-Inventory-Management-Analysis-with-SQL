-- Create the database
CREATE DATABASE Medical_Inventory_and_Supply_Chain_Optimization;
USE Medical_Inventory_and_Supply_Chain_Optimization;

-- Create the 5 tables 
-- Create Inventory Table
CREATE TABLE Inventory (
    Item_ID INT PRIMARY KEY,
    Item_Name VARCHAR(100) NOT NULL,
    Category VARCHAR(50) NOT NULL,
    Stock_Level INT NOT NULL,
    Reorder_Threshold INT NOT NULL,
    Facility_ID INT NOT NULL,
    Last_Updated DATE NOT NULL
);

-- Create Suppliers Table
CREATE TABLE Suppliers (
    Supplier_ID INT PRIMARY KEY,
    Supplier_Name VARCHAR(150) NOT NULL,
    Item_ID INT NOT NULL,
    Lead_Time_Days INT NOT NULL,
    FOREIGN KEY (Item_ID) REFERENCES Inventory(Item_ID)
);

-- Create Orders Table
CREATE TABLE Orders (
    Order_ID INT PRIMARY KEY,
    Item_ID INT NOT NULL,
    Order_Date DATE NOT NULL,
    Quantity INT NOT NULL,
    Status VARCHAR(50) NOT NULL,
    FOREIGN KEY (Item_ID) REFERENCES Inventory(Item_ID)
);

-- Create Sales Table
CREATE TABLE Sales (
    Sale_ID INT PRIMARY KEY,
    Item_ID INT NOT NULL,
    Facility_ID INT NOT NULL,
    Sale_Date DATE NOT NULL,
    Quantity_Sold INT NOT NULL,
    FOREIGN KEY (Item_ID) REFERENCES Inventory(Item_ID),
    FOREIGN KEY (Facility_ID) REFERENCES Facilities(Facility_ID)
);

-- Create Facilities Table
CREATE TABLE Facilities (
    Facility_ID INT PRIMARY KEY,
    Facility_Name VARCHAR(100) NOT NULL,
    Region VARCHAR(50) NOT NULL
);

-- 1.Inventory Management:
-- Which items are below their reorder thresholds and need immediate restocking
SELECT f.Facility_ID, i.Item_Name, i.Category, i.Stock_Level, i.Reorder_Threshold
FROM inventory i
JOIN facilities f
ON i.Facility_ID = f.Facility_ID
WHERE Stock_Level < Reorder_Threshold
ORDER BY 5;

-- Which facilities frequently have stockouts
SELECT f.Region, COUNT(f.Facility_Name) Facility_Stockout, i.Stock_Level, i.Reorder_Threshold
FROM facilities f
JOIN inventory i ON f.Facility_ID = i.Facility_ID
WHERE i.Stock_Level < i.Reorder_Threshold
GROUP BY 1, 3, 4
ORDER BY 4 DESC
LIMIT 10;

-- Average lead time for each supplier and its impact on stock levels.
SELECT s.Supplier_Name, ROUND(AVG(s.Lead_Time_Days)) Avg_Lead_Time, ROUND(AVG(i.Stock_Level)) Avg_Stock_Level,
    SUM(CASE 
        WHEN i.Stock_Level < i.Reorder_Threshold THEN 1 
        ELSE 0 
    END) AS Stockouts
FROM Suppliers s
JOIN Inventory i ON s.Item_ID = i.Item_ID
GROUP BY 1
ORDER BY 2 ASC;
-- Analysis:
-- Suppliers with shorter lead times tend to have higher average stock levels and fewer stockouts, as they replenish inventory more efficiently.
-- Suppliers with longer lead times may contribute to frequent stockouts, especially if reorder planning isn't adjusted to account for the delays.
-- Next Steps
-- Optimize Orders: Plan orders earlier for suppliers with higher average lead times.
-- Adjust Reorder Thresholds: For suppliers with long lead times, consider increasing the reorder threshold to prevent stockouts.
-- Supplier Evaluation: Identify underperforming suppliers based on lead time and stockout metrics to reevaluate contracts or find alternatives.

-- 2.Supply Chain Analysis:
-- What is the total time taken for orders to be fulfilled across regions
SELECT f.Region,SUM(s.Lead_Time_Days) Total_Fulfillment_Time
FROM Orders o
JOIN Inventory i
ON o.Item_ID = i.Item_ID
JOIN Facilities f
ON i.Facility_ID = f.Facility_ID
JOIN Suppliers s
ON i.Item_ID = s.Item_ID
WHERE o.Status = 'Delivered'
GROUP BY 1
ORDER BY 2 DESC;

-- Identify delays in order deliveries based on supplier lead times and pending statuses.
SELECT 
    i.item_id,
    i.Item_Name,
    s.Supplier_Name,
    f.Facility_Name,
    f.Region,
    o.Order_Date,
    DATE_ADD(o.Order_Date, INTERVAL s.Lead_Time_Days DAY) Expected_Delivery_Date,
    DATEDIFF(CURRENT_DATE, DATE_ADD(o.Order_Date, INTERVAL s.Lead_Time_Days DAY)) Delay_Days,
    o.Status
FROM Orders o
JOIN Inventory i
ON o.Item_ID = i.Item_ID
JOIN Suppliers s
ON i.Item_ID = s.Item_ID
JOIN Facilities f
ON i.Facility_ID = f.Facility_ID
WHERE o.Status IN ('Pending') AND CURRENT_DATE > DATE_ADD(o.Order_Date, INTERVAL s.Lead_Time_Days DAY)
ORDER BY 8 DESC;

-- 3.Sales Trends:
-- Which medical supplies are the most sold across all regions
SELECT f.Region, i.Item_ID, i.Item_Name, i.Category, SUM(s.Quantity_Sold) Quantity_Sold
FROM facilities f
JOIN inventory i
ON f.Facility_ID = i.Facility_ID
JOIN sales s
ON f.Facility_ID = s.Facility_ID
GROUP BY 1, 2, 3, 4
ORDER BY 5 DESC
LIMIT 10;

-- Seasonal trends in sales for specific categories (e.g., vaccines during flu season).
SELECT i.Category,MONTH(s.Sale_Date) Sale_Month, YEAR(s.Sale_Date) Sale_Year,f.Region,SUM(s.Quantity_Sold) Total_Sales,
ROUND(AVG(s.Quantity_Sold),2) Avg_Sales
FROM Sales s
JOIN Inventory i ON s.Item_ID = i.Item_ID
JOIN Facilities f ON s.Facility_ID = f.Facility_ID
-- WHERE i.Category = 'Vaccines'
GROUP BY 1, 2, 3, 4
ORDER BY 2, 3, 5 DESC;
-- LIMIT 10;

-- 4.Regional Performance:
-- Which regions have the highest and lowest sales of medical supplies
SELECT f.Region,SUM(s.Quantity_Sold) Total_Sales
FROM Sales s
JOIN Inventory i
ON s.Item_ID = i.Item_ID
JOIN Facilities f
ON i.Facility_ID = f.Facility_ID
GROUP BY 1
ORDER BY 2 DESC;
-- or use a query with window functions to explicitly identify the regions with the highest and lowest sales and others.
WITH Regional_Sales AS (
    SELECT f.Region,SUM(s.Quantity_Sold) AS Total_Sales
    FROM Sales s
    JOIN Inventory i
    ON s.Item_ID = i.Item_ID
    JOIN Facilities f
    ON i.Facility_ID = f.Facility_ID
    GROUP BY 1
)
SELECT Region,Total_Sales,
    CASE
        WHEN Total_Sales = (SELECT MAX(Total_Sales) FROM Regional_Sales) THEN 'Highest'
        WHEN Total_Sales = (SELECT MIN(Total_Sales) FROM Regional_Sales) THEN 'Lowest'
        ELSE 'Others'
    END Sales_level
FROM Regional_Sales
ORDER BY 2 DESC;

-- Correlation between sales trends and inventory restocking patterns
-- Create Restocks Table 
CREATE TABLE Restocks (
    Restock_ID INT PRIMARY KEY,
    Item_ID INT NOT NULL,
    Restock_Date DATE NOT NULL,
    Quantity_Restocked INT NOT NULL,
    FOREIGN KEY (Item_ID) REFERENCES Inventory(Item_ID)
);

-- Aggregate Sales Trends
WITH SalesTrends AS (
    SELECT 
        DATE_FORMAT(Sale_Date, '%Y-%m') Month,
        Item_ID,
        SUM(Quantity_Sold) Total_Sales
    FROM Sales
    GROUP BY 1, 2
),

-- Aggregate Restocking Trends
RestockingTrends AS (
    SELECT 
        DATE_FORMAT(Restock_Date, '%Y-%m') AS Month,
        Item_ID,
        SUM(Quantity_Restocked) AS Total_Restocked
    FROM Restocks
    GROUP BY Month, Item_ID
)

-- Combine Sales and Restocking Data
SELECT 
    st.Month,
    st.Item_ID,
    st.Total_Sales,
    rt.Total_Restocked
FROM SalesTrends st
LEFT JOIN RestockingTrends rt
ON st.Month = rt.Month AND st.Item_ID = rt.Item_ID
ORDER BY st.Month, st.Item_ID;
-- Imported the query to Python for correlation analysis since SQL is not good for complex statistic like correlation as shown below
-- correlation = sales_restocking[['Total_Sales', 'Total_Restocked']].corr()
-- Insights:
-- A high positive correlation indicates that restocking patterns closely follow sales trends.
-- A low or negative correlation may indicate inefficiencies in restocking (overstocking or delayed restocking).

-- 5.Demand Forecasting:
-- Predict demand for specific items based on past sales trends
WITH MonthlySales AS (
    SELECT 
        i.Item_ID,i.Item_Name,i.Category,
        DATE_FORMAT(s.Sale_Date, '%Y-%m') Sale_Month,
        SUM(s.Quantity_Sold) Total_Sales
    FROM Sales s
    JOIN Inventory i
    ON s.Item_ID = i.Item_ID
    GROUP BY 1, 2, 3, 4
),
DemandPrediction AS (
    SELECT 
        Item_ID,Item_Name,Category,
        ROUND(AVG(Total_Sales), 2) Average_Monthly_Sales,
        MAX(Total_Sales) Peak_Monthly_Sales,
        MIN(Total_Sales) Low_Monthly_Sales
    FROM MonthlySales
    GROUP BY 1, 2, 3
)
SELECT 
    dp.Item_ID,dp.Item_Name,dp.Category,dp.Average_Monthly_Sales,dp.Peak_Monthly_Sales,dp.Low_Monthly_Sales,
    CASE 
        WHEN dp.Average_Monthly_Sales > i.Reorder_Threshold THEN 'High Demand'
        WHEN dp.Average_Monthly_Sales BETWEEN (i.Reorder_Threshold * 0.5) AND i.Reorder_Threshold THEN 'Moderate Demand'
        ELSE 'Low Demand'
    END AS Demand_Level
FROM DemandPrediction dp
JOIN Inventory i
ON dp.Item_ID = i.Item_ID
ORDER BY dp.Average_Monthly_Sales DESC;
-- Insights:
-- High-Demand Items- Items that consistently sell more than their reorder threshold should be prioritized for restocking.
-- Seasonal Peaks- Peaks in sales can indicate seasonal demand, e.g., vaccines during flu seasons.
-- Demand Levels- Helps facilities prioritize inventory management for specific products

-- Identify underperforming regions with potential supply-demand gaps.
WITH RegionalSales AS (
    SELECT f.Region,i.Item_ID,Item_Name,Category,SUM(s.Quantity_Sold) Total_Demand,SUM(i.Stock_Level) Total_Supply
    FROM Sales s
    JOIN Inventory i ON s.Item_ID = i.Item_ID
    JOIN Facilities f ON s.Facility_ID = f.Facility_ID
    GROUP BY f.Region, i.Item_ID
)
SELECT Region,Item_ID,Item_Name,Category,Total_Demand,
    COALESCE(Total_Supply, 0) Total_Supply,
    Total_Demand - COALESCE(Total_Supply, 0) Supply_Demand_Gap
FROM RegionalSales
WHERE Total_Demand > COALESCE(Total_Supply,0)
ORDER BY Supply_Demand_Gap DESC;
-- Insights:
-- Item_Name(Student) with Item_ID(189) in category(Medine) in Nairobi is the highest with supply demand gap
-- Item_Name(Invoice) with Item_ID(78) in Category(Equipment) in Eldorect is the lowest with supply demand gap

