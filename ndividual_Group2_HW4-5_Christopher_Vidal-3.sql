USE WideWorldImporters;
GO




/* lines priced above that order’s average line price */
SELECT OL.OrderID, OL.OrderLineID, OL.StockItemID, OL.UnitPrice   -- pick line basics and price
FROM Sales.OrderLines AS OL  -- from order lines table
WHERE OL.UnitPrice >  -- keep lines where price is greater than...
(   -- start subquery to get that order's avg price
  SELECT AVG(OL2.UnitPrice)  -- average line price for the order
  FROM Sales.OrderLines AS OL2   -- look at all lines for that order
  WHERE OL2.OrderID = OL.OrderID  -- same order as the outer row
);     -- end subquery and comparison


/* customers with no invoices in 2016 */
SELECT C.CustomerID, C.CustomerName  -- show id and name
FROM Sales.Customers AS C  -- from customers
WHERE NOT EXISTS   -- keep only if the following set is empty
(   -- start anti-subquery
  SELECT 1   -- just needs to find a row, any row
  FROM Sales.Invoices AS I   -- check invoices
  WHERE I.CustomerID = C.CustomerID   -- for this customer
    AND I.InvoiceDate >= '20160101' AND I.InvoiceDate < '20170101'  -- in calendar year 2016
);     -- no rows found = no invoices that year


/* first invoice per customer */
SELECT I.CustomerID, I.InvoiceID, I.InvoiceDate -- return the first invoice info
FROM Sales.Invoices AS I   -- from invoices
WHERE I.InvoiceDate =  -- match the earliest date for this customer
(   -- subquery to get earliest date
  SELECT TOP (1) I2.InvoiceDate  -- pick the first date after sorting ascending
  FROM Sales.Invoices AS I2  -- same invoices table
  WHERE I2.CustomerID = I.CustomerID  -- same customer
  ORDER BY I2.InvoiceDate ASC, I2.InvoiceID ASC  -- earliest date, tie-break by id
)   -- end earliest-date subquery
AND I.InvoiceID =  -- also make sure we pick the exact first row
(   -- subquery to get the first row (date + id)
  SELECT TOP (1) I3.InvoiceID   -- take the id of the first chronological invoice
  FROM Sales.Invoices AS I3   -- same invoices table
  WHERE I3.CustomerID = I.CustomerID   -- same customer
  ORDER BY I3.InvoiceDate ASC, I3.InvoiceID ASC  -- earliest date then smallest id
);  -- end first-row subquery


/* cities with more suppliers than customers */
WITH CustCnt AS   -- CTE: customer counts per city
(   -- open CTE body
  SELECT DeliveryCityID AS CityID, COUNT(*) AS NumCustomers   -- city id and number of customers
  FROM Sales.Customers  -- from customers
  GROUP BY DeliveryCityID  -- group by city
), -- end first CTE
SuppCnt AS   -- CTE: supplier counts per city
(  -- open second CTE body
  SELECT DeliveryCityID AS CityID, COUNT(*) AS NumSuppliers   -- city id and number of suppliers
  FROM Purchasing.Suppliers   -- from suppliers
  GROUP BY DeliveryCityID  -- group by city
)  -- end second CTE
SELECT COALESCE(s.CityID, c.CityID) AS CityID,  -- pick the city id from either side
       COALESCE(c.NumCustomers, 0) AS NumCustomers,  -- customers count, 0 if missing
       COALESCE(s.NumSuppliers, 0) AS NumSuppliers  -- suppliers count, 0 if missing
FROM SuppCnt AS s  -- start from supplier counts
FULL JOIN CustCnt AS c   -- full join to include cities missing on either side
  ON c.CityID = s.CityID   -- join on city
WHERE COALESCE(s.NumSuppliers, 0) > COALESCE(c.NumCustomers, 0);    -- keep cities with more suppliers than customers


/* CROSS APPLY – top 2 most valuable lines per invoice */
SELECT I.InvoiceID, A.InvoiceLineID, A.StockItemID, A.UnitPrice, A.Quantity, A.LineTotal  -- invoice and its top lines
FROM Sales.Invoices AS I  -- each invoice
CROSS APPLY   -- per invoice, attach a small top-N result
(  -- derived subquery for top lines
  SELECT TOP (2) IL.InvoiceLineID, IL.StockItemID, IL.UnitPrice, IL.Quantity, -- take top 2 lines
         (IL.UnitPrice * IL.Quantity) AS LineTotal  -- compute line total
  FROM Sales.InvoiceLines AS IL -- from invoice lines
  WHERE IL.InvoiceID = I.InvoiceID  -- only lines for this invoice
  ORDER BY (IL.UnitPrice * IL.Quantity) DESC, IL.InvoiceLineID DESC -- highest value first, stable tie-break
) AS A;  -- end APPLY as alias A


/* customers who bought at least one item in every color */
SELECT C.CustomerID, C.CustomerName     -- show the customers
FROM Sales.Customers AS C    -- from customers
WHERE NOT EXISTS -- keep only if there is no missing color
(   -- start "for all colors" check
  SELECT 1  -- look for a color the customer did NOT buy
  FROM (SELECT DISTINCT ColorID  -- list all colors that exist
        FROM Warehouse.StockItems   -- from stock items
        WHERE ColorID IS NOT NULL) AS Colors  -- ignore null colors
  WHERE NOT EXISTS  -- if we find a color with no matching purchase -> fail
  ( -- inner check: did they buy this color?
    SELECT 1 -- any matching row works
    FROM Sales.Invoices AS I  -- invoices for the customer
    JOIN Sales.InvoiceLines AS IL ON IL.InvoiceID = I.InvoiceID  -- join to lines
    JOIN Warehouse.StockItems AS SI ON SI.StockItemID = IL.StockItemID -- join to items to get color
    WHERE I.CustomerID = C.CustomerID -- same customer
      AND SI.ColorID = Colors.ColorID -- matches this color
  ) -- end inner NOT EXISTS
);  -- if no missing color found, customer passes


/* first purchase order per supplier, including suppliers with none */
SELECT S.SupplierID, S.SupplierName, A.PurchaseOrderID, A.OrderDate -- supplier and their first PO (or nulls)
FROM Purchasing.Suppliers AS S -- all suppliers
OUTER APPLY  -- allow suppliers with no PO (returns nulls)
(  -- subquery to grab the first PO
  SELECT TOP (1) PO.PurchaseOrderID, PO.OrderDate -- take the earliest order
  FROM Purchasing.PurchaseOrders AS PO -- from purchase orders
  WHERE PO.SupplierID = S.SupplierID -- for this supplier
  ORDER BY PO.OrderDate ASC, PO.PurchaseOrderID ASC -- earliest date, tie-break by id
) AS A;  -- end APPLY as alias A


/* items ever purchased but never sold */
SELECT SI.StockItemID, SI.StockItemName  -- return item id and name
FROM Warehouse.StockItems AS SI -- from items list
WHERE EXISTS -- must have at least one purchase record
(  -- check purchases
  SELECT 1 -- any row proves it was purchased
  FROM Purchasing.PurchaseOrderLines AS POL  -- purchase order lines
  WHERE POL.StockItemID = SI.StockItemID  -- same item
)    -- end purchase check
AND NOT EXISTS    -- and must have zero sales records
(   -- check sales
  SELECT 1  -- any row would mean it was sold
  FROM Sales.InvoiceLines AS IL  -- invoice lines
  WHERE IL.StockItemID = SI.StockItemID  -- same item
);  -- end sales check (no rows = never sold)


/*countries where every supplier has at least one PO */
SELECT Ctry.CountryName  -- list country names
FROM Application.Countries AS Ctry   -- from countries table
WHERE NOT EXISTS   -- keep if we do NOT find a failing supplier
(   -- start search for a supplier with no PO
  SELECT 1  -- any hit means the country fails
  FROM Purchasing.Suppliers AS S  -- suppliers in that country
  JOIN Application.Cities AS Ci -- join to cities
    ON Ci.CityID = S.DeliveryCityID   -- supplier city
  JOIN Application.StateProvinces AS SP  -- join to states/provinces
    ON SP.StateProvinceID = Ci.StateProvinceID -- link city->state
  WHERE SP.CountryID = Ctry.CountryID -- filter suppliers in this country
    AND NOT EXISTS  -- supplier fails if they have no POs
    ( -- check for at least one PO
      SELECT 1   -- any PO is enough
      FROM Purchasing.PurchaseOrders AS PO  -- purchase orders
      WHERE PO.SupplierID = S.SupplierID   -- for this supplier
    )  -- end supplier PO check
);  -- if no failing supplier, include country


/* 5 most recent invoices per customer with totals */
SELECT C.CustomerID, C.CustomerName, A.InvoiceID, A.InvoiceDate, A.InvoiceTotal  -- customer and their recent invoices
FROM Sales.Customers AS C       -- all customers
CROSS APPLY   -- attach up to 5 latest invoices per customer
(       -- subquery for top 5 invoices with totals
  SELECT TOP (5) I.InvoiceID, I.InvoiceDate,  -- pick 5 newest invoices
         (SELECT SUM(IL.UnitPrice * IL.Quantity) -- sum line totals for that invoice
          FROM Sales.InvoiceLines AS IL  -- from invoice lines
          WHERE IL.InvoiceID = I.InvoiceID) AS InvoiceTotal  -- lines that belong to this invoice
  FROM Sales.Invoices AS I    -- invoices table
  WHERE I.CustomerID = C.CustomerID    -- only this customer's invoices
  ORDER BY I.InvoiceDate DESC, I.InvoiceID DESC   -- newest first, tie-break by id
) AS A  -- end APPLY
ORDER BY C.CustomerID, A.InvoiceDate DESC, A.InvoiceID DESC;   -- final ordering of output

