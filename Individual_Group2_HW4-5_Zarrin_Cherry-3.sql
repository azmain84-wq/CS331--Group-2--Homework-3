USE WideWorldImporters;

-- CSCI 331 – HW 4 & 5 (Ch. 4: Subqueries; Ch. 5: Table Expressions)
-- Named Database: WideWorldImporters
-- Student: Zarrin Cherry | Group: 2
-- NOTE: Only subqueries + table expressions (derived tables, CTEs, APPLY). No window functions, no set operators.

/* Proposition 1 (Ch4: NOT EXISTS – customers with no orders in 2015) */
SELECT C.CustomerID, C.CustomerName
FROM Sales.Customers AS C
WHERE NOT EXISTS
(
  SELECT 1
  FROM Sales.Orders AS O
  WHERE O.CustomerID = C.CustomerID
    AND O.OrderDate >= '20150101' AND O.OrderDate < '20160101'
);

/* Proposition 2 (Ch4: scalar subquery – orders above that customer’s average) */
SELECT O.OrderID, O.CustomerID, SUM(OL.UnitPrice * OL.Quantity) AS OrderTotal
FROM Sales.Orders AS O
JOIN Sales.OrderLines AS OL
  ON OL.OrderID = O.OrderID
GROUP BY O.OrderID, O.CustomerID
HAVING SUM(OL.UnitPrice * OL.Quantity) >
(
  SELECT AVG(T.OrderTotal)
  FROM (
      SELECT O2.OrderID, SUM(OL2.UnitPrice * OL2.Quantity) AS OrderTotal
      FROM Sales.Orders AS O2
      JOIN Sales.OrderLines AS OL2
        ON OL2.OrderID = O2.OrderID
      WHERE O2.CustomerID = O.CustomerID
      GROUP BY O2.OrderID
  ) AS T
);

/* Proposition 3 (Ch4: relational division via double NOT EXISTS) */
SELECT S.SupplierID, S.SupplierName
FROM Purchasing.Suppliers AS S
WHERE NOT EXISTS
(
  SELECT 1
  FROM (SELECT DISTINCT ColorID FROM Warehouse.StockItems WHERE ColorID IS NOT NULL) AS Colors
  WHERE NOT EXISTS
  (
    SELECT 1
    FROM Purchasing.PurchaseOrderLines AS POL
    JOIN Purchasing.PurchaseOrders AS PO ON PO.PurchaseOrderID = POL.PurchaseOrderID
    WHERE PO.SupplierID = S.SupplierID
      AND POL.StockItemID IN (SELECT SI.StockItemID FROM Warehouse.StockItems AS SI WHERE SI.ColorID = Colors.ColorID)
  )
);

/* Proposition 4 (Ch4: correlated subquery – last order per customer) */
SELECT O.CustomerID, O.OrderID, O.OrderDate
FROM Sales.Orders AS O
WHERE O.OrderDate = 
(
  SELECT TOP (1) O2.OrderDate
  FROM Sales.Orders AS O2
  WHERE O2.CustomerID = O.CustomerID
  ORDER BY O2.OrderDate DESC, O2.OrderID DESC
)
AND O.OrderID =
(
  SELECT TOP (1) O3.OrderID
  FROM Sales.Orders AS O3
  WHERE O3.CustomerID = O.CustomerID
  ORDER BY O3.OrderDate DESC, O3.OrderID DESC
);

/* Proposition 5 (Ch5: CTE – cities with more customers than suppliers) */
WITH CustCounts AS
(
  SELECT DeliveryCityID AS CityID, COUNT(*) AS NumCustomers
  FROM Sales.Customers
  GROUP BY DeliveryCityID
),
SuppCounts AS
(
  SELECT DeliveryCityID AS CityID, COUNT(*) AS NumSuppliers
  FROM Purchasing.Suppliers
  GROUP BY DeliveryCityID
)
SELECT COALESCE(c.CityID, s.CityID) AS CityID,
       COALESCE(c.NumCustomers, 0) AS NumCustomers,
       COALESCE(s.NumSuppliers, 0) AS NumSuppliers
FROM CustCounts AS c
FULL JOIN SuppCounts AS s
  ON s.CityID = c.CityID
WHERE COALESCE(c.NumCustomers, 0) > COALESCE(s.NumSuppliers, 0);

/* Proposition 6 (Ch5: CROSS APPLY – top 1 most expensive line per order) */
SELECT O.OrderID, A.StockItemID, A.UnitPrice, A.Quantity, A.LineProfit
FROM Sales.Orders AS O
CROSS APPLY
(
  SELECT TOP (1) OL.StockItemID, OL.UnitPrice, OL.Quantity,
         (OL.UnitPrice * OL.Quantity) AS LineProfit
  FROM Sales.OrderLines AS OL
  WHERE OL.OrderID = O.OrderID
  ORDER BY (OL.UnitPrice * OL.Quantity) DESC, OL.OrderLineID DESC
) AS A;

/* Proposition 7 (Ch5: OUTER APPLY – first invoice per customer, allowing customers with none) */
SELECT C.CustomerID, C.CustomerName, A.InvoiceID, A.InvoiceDate
FROM Sales.Customers AS C
OUTER APPLY
(
  SELECT TOP (1) I.InvoiceID, I.InvoiceDate
  FROM Sales.Invoices AS I
  WHERE I.CustomerID = C.CustomerID
  ORDER BY I.InvoiceDate ASC, I.InvoiceID ASC
) AS A;

/* Proposition 8 (Ch4: semi/anti – items with warehouse activity but never sold) */
SELECT SI.StockItemID, SI.StockItemName
FROM Warehouse.StockItems AS SI
WHERE EXISTS
(
  SELECT 1
  FROM Warehouse.StockItemTransactions AS T
  WHERE T.StockItemID = SI.StockItemID
)
AND NOT EXISTS
(
  SELECT 1
  FROM Sales.InvoiceLines AS IL
  WHERE IL.StockItemID = SI.StockItemID
);

/* Proposition 9 (Ch4: NOT EXISTS nesting – countries where every customer placed at least one order) */
SELECT Ctry.CountryName
FROM Application.Countries AS Ctry
WHERE NOT EXISTS
(
  SELECT 1
  FROM Sales.Customers AS C
  JOIN Application.Cities AS Ci
    ON Ci.CityID = C.DeliveryCityID
  JOIN Application.StateProvinces AS SP
    ON SP.StateProvinceID = Ci.StateProvinceID
  WHERE SP.CountryID = Ctry.CountryID
    AND NOT EXISTS
    (
      SELECT 1
      FROM Sales.Orders AS O
      WHERE O.CustomerID = C.CustomerID
    )
);

/* Proposition 10 (Ch5: derived table + APPLY – 3 most recent orders per customer with totals) */
SELECT C.CustomerID, C.CustomerName, A.OrderID, A.OrderDate, A.OrderTotal
FROM Sales.Customers AS C
CROSS APPLY
(
  SELECT TOP (3) O.OrderID, O.OrderDate,
         (SELECT SUM(OL.UnitPrice * OL.Quantity)
          FROM Sales.OrderLines AS OL
          WHERE OL.OrderID = O.OrderID) AS OrderTotal
  FROM Sales.Orders AS O
  WHERE O.CustomerID = C.CustomerID
  ORDER BY O.OrderDate DESC, O.OrderID DESC
) AS A
ORDER BY C.CustomerID, A.OrderDate DESC, A.OrderID DESC;
