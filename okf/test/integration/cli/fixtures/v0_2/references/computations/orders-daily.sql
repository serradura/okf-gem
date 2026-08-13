SELECT order_date AS day, COUNT(*) AS orders
FROM `sales.orders`
GROUP BY day
ORDER BY day
