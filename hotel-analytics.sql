-- Calculates the occupancy rate (percentage of filled rooms) for each hotel

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    COUNT(DISTINCT rr.RES_ROOMS_ID) AS occupied_room_count,      
    SUM(rt.MAX_AVAB) AS total_room_count,                        
    ROUND(COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB), 2) AS occupancy_rate_percent 
FROM tbl_otels o
JOIN tbl_room_types rt ON rt.OTEL_ID = o.OTEL_ID
JOIN tbl_reservation_rooms rr ON rr.room_type_id = rt.ROOM_TYPE_ID
JOIN tbl_reservations r ON r.reservation_id = rr.reservation_id
WHERE r.state IN ('Realized', 'Approved', 'Saved')
GROUP BY o.OTEL_ID, o.OTEL_NAME;

-- Alternative (Advanced) version using a CTE (Common Table Expression)

WITH occupancy AS (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        COUNT(DISTINCT rr.RES_ROOM_ID) AS occupied_room_count,   
        SUM(rt.MAX_AVAB) AS total_room_count                     
    FROM tbl_otels o
    JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
    JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
    JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
    WHERE r.STATE IN ('Realized', 'Approved')
    GROUP BY o.OTEL_ID, o.OTEL_NAME
)
SELECT
    OTEL_ID,
    OTEL_NAME,
    occupied_room_count,
    total_room_count,
    ROUND(occupied_room_count * 100.0 / total_room_count, 2) AS occupancy_rate_percent
FROM occupancy
LIMIT 5;

-- Average Daily Rate (ADR) = Total Revenue / Total Number of Rooms

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    ROUND(SUM(rp.PRICE) / COUNT(DISTINCT rr.RES_ROOMS_ID), 2) AS Average_Daily_Rate
FROM tbl_otels o
JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
JOIN tbl_reservation_room_prices rp ON rp.RES_ROOMS_ID = rr.RES_ROOMS_ID
WHERE r.STATE IN ('Realized')
GROUP BY o.OTEL_ID, o.OTEL_NAME
LIMIT 5;


-- Detailed ADR Calculations by Reservation State

SELECT 
    OTEL_ID, 
    OTEL_NAME, 

    ROUND(
        SUM(CASE WHEN r.STATE = 'Realized' THEN rp.TOTAL_PRICE ELSE 0 END)
        / COUNT(DISTINCT CASE WHEN r.STATE = 'Realized' THEN rr.RES_ROOMS_ID END), 
        2
    ) AS ADR_Realized,

    ROUND(
        SUM(CASE WHEN r.STATE IN ('Realized','Approved') THEN rp.TOTAL_PRICE ELSE 0 END)
        / COUNT(DISTINCT CASE WHEN r.STATE IN ('Realized','Approved') THEN rr.RES_ROOMS_ID END), 
        2
    ) AS ADR_Operational,

    ROUND(
        SUM(CASE 
            WHEN r.STATE = 'Approved' AND r.check_in_date >= CURDATE() 
            THEN rp.TOTAL_PRICE 
            ELSE 0 
        END)
        / COUNT(DISTINCT CASE 
            WHEN r.STATE = 'Approved' AND r.check_in_date >= CURDATE() 
            THEN rr.RES_ROOMS_ID 
        END), 
        2
    ) AS ADR_Forecast,

    ROUND(
        SUM(CASE WHEN r.STATE IN ('Realized','Approved') THEN rp.TOTAL_PRICE ELSE 0 END)
        / SUM(CASE WHEN r.STATE IN ('Realized','Approved') THEN DATEDIFF(r.check_out_date, r.check_in_date) ELSE 0 END), 
        2
    ) AS ADR_Normalized
FROM tbl_otels o
JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
JOIN tbl_reservation_room_prices rp ON rp.RES_ROOMS_ID = rr.RES_ROOMS_ID
GROUP BY OTEL_ID, OTEL_NAME
LIMIT 5;

-- Daily Revenue per Room (RevPAR-like calculation)

WITH RevenueCalc AS (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        rr.RES_ROOMS_ID,
        r.check_in_date,     
        rp.TOTAL_PRICE AS room_revenue,
        COALESCE(SUM(rex.PRICE), 0) AS extra_revenue,
        COALESCE(SUM(tax.AMOUNT), 0) AS tax_revenue,
        COALESCE(SUM(pd.DISCOUNT_AMOUNT), 0) AS promo_discount
    FROM tbl_otels o
    JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
    JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
    JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
    JOIN tbl_reservation_room_prices rp ON rp.RES_ROOMS_ID = rr.RES_ROOMS_ID
    
    LEFT JOIN tbl_reservation_room_extras rex ON rex.RES_ROOMS_ID = rr.RES_ROOMS_ID
    LEFT JOIN tbl_extras e ON e.EXTRA_ID = rex.EXTRA_ID
    
    LEFT JOIN tbl_reservation_applied_taxes tax ON tax.RESERVATION_ID = r.RESERVATION_ID
    
    LEFT JOIN tbl_special_discounts pd ON pd.RESERVATION_ID = r.RESERVATION_ID
    
    WHERE r.STATE = 'Realized'
    GROUP BY o.OTEL_ID, o.OTEL_NAME, rr.RES_ROOMS_ID, r.check_in_date, rp.TOTAL_PRICE
)

SELECT
    OTEL_ID,
    OTEL_NAME,
    DATE(check_in_date) AS Date,

    -- Total Revenue = Room + Extras + Tax - Discount
    ROUND(SUM(room_revenue + extra_revenue + tax_revenue - promo_discount), 2) AS Total_Revenue,

    SUM(rt.MAX_AVAB) AS Total_Room_Count,

    -- Revenue per Available Room (Daily)
    ROUND(
        SUM(room_revenue + extra_revenue + tax_revenue - promo_discount) / SUM(rt.MAX_AVAB),
        2
    ) AS Revenue_per_Room_Day

FROM RevenueCalc gh
JOIN tbl_room_types rt ON rt.ROOM_TYPE_ID IN (
    SELECT ROOM_TYPE_ID
    FROM tbl_reservation_rooms
    WHERE RES_ROOMS_ID = gh.RES_ROOMS_ID
)
GROUP BY OTEL_ID, OTEL_NAME, DATE(check_in_date)
ORDER BY OTEL_ID, Date
LIMIT 20;

-- Weekday vs Weekend Occupancy Comparison

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    CASE
        WHEN WEEKDAY(r.check_in_date) BETWEEN 0 AND 4 THEN 'Weekday'
        ELSE 'Weekend'
    END AS Day_Type,
    COUNT(DISTINCT rr.RES_ROOMS_ID) AS Occupied_Room_Count,
    SUM(rt.MAX_AVAB) AS Total_Room_Count,
    ROUND(COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB), 2) AS Occupancy_Rate_Percent
FROM tbl_otels o
JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
WHERE r.STATE = 'Realized'
GROUP BY o.OTEL_ID, o.OTEL_NAME, Day_Type
ORDER BY Day_Type ASC, o.OTEL_ID;


-- Weekday vs Weekend Occupancy with Row Number for Ordering

SELECT
    OTEL_ID,
    OTEL_NAME,
    Day_Type,
    Occupied_Room_Count,
    Total_Room_Count,
    Occupancy_Rate_Percent,
    ROW_NUMBER() OVER(
        PARTITION BY OTEL_ID 
        ORDER BY CASE WHEN Day_Type = 'Weekday' THEN 1 ELSE 2 END
    ) AS Row_Num
FROM (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        CASE
            WHEN WEEKDAY(r.check_in_date) BETWEEN 0 AND 4 THEN 'Weekday'
            ELSE 'Weekend'
        END AS Day_Type,
        COUNT(DISTINCT rr.RES_ROOMS_ID) AS Occupied_Room_Count,
        SUM(rt.MAX_AVAB) AS Total_Room_Count,
        ROUND(COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB), 2) AS Occupancy_Rate_Percent
    FROM tbl_otels o
    JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
    JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
    JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
    WHERE r.STATE = 'Realized'
    GROUP BY o.OTEL_ID, o.OTEL_NAME, Day_Type
) AS Occupancy_Table
ORDER BY OTEL_ID, Row_Num;

-- Weekday vs Weekend Occupancy Difference by Hotel (with CTE)

WITH Occupancy AS (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        CASE
            WHEN WEEKDAY(r.check_in_date) BETWEEN 0 AND 4 THEN 'Weekday'
            ELSE 'Weekend'
        END AS Day_Type,
        COUNT(DISTINCT rr.RES_ROOMS_ID) AS Occupied_Room_Count,
        SUM(rt.MAX_AVAB) AS Total_Room_Count,
        ROUND(COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB), 2) AS Occupancy_Rate_Percent
    FROM tbl_otels o
    JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
    JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
    JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
    WHERE r.STATE = 'Realized'
    GROUP BY o.OTEL_ID, o.OTEL_NAME, Day_Type
)

SELECT
    d.OTEL_ID,
    d.OTEL_NAME,
    MAX(CASE WHEN Day_Type = 'Weekday' THEN Occupancy_Rate_Percent END) AS Weekday_Occupancy,
    MAX(CASE WHEN Day_Type = 'Weekend' THEN Occupancy_Rate_Percent END) AS Weekend_Occupancy,
    ROUND(
        MAX(CASE WHEN Day_Type = 'Weekend' THEN Occupancy_Rate_Percent END) -
        MAX(CASE WHEN Day_Type = 'Weekday' THEN Occupancy_Rate_Percent END),
        2
    ) AS Weekend_Weekday_Difference
FROM Occupancy d
GROUP BY d.OTEL_ID, d.OTEL_NAME
ORDER BY d.OTEL_ID;

-- Seasonal Occupancy Trends

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    CASE
        WHEN MONTH(r.check_in_date) IN (12, 1, 2) THEN 'Winter'
        WHEN MONTH(r.check_in_date) IN (3, 4, 5) THEN 'Spring'
        WHEN MONTH(r.check_in_date) IN (6, 7, 8) THEN 'Summer'
        ELSE 'Autumn'
    END AS Season,
    COUNT(DISTINCT rr.RES_ROOMS_ID) AS Occupied_Room_Count,
    SUM(rt.MAX_AVAB) AS Total_Room_Count,
    ROUND(COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB), 2) AS Occupancy_Rate_Percent
FROM tbl_otels o
JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
WHERE r.STATE = 'Realized'
GROUP BY o.OTEL_ID, o.OTEL_NAME, Season
ORDER BY o.OTEL_ID, FIELD(Season, 'Winter', 'Spring', 'Summer', 'Autumn');

-- Monthly Occupancy Trends

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    YEAR(r.check_in_date) AS Year,
    MONTH(r.check_in_date) AS Month,
    COUNT(DISTINCT rr.RES_ROOMS_ID) AS Occupied_Room_Count,
    SUM(rt.MAX_AVAB) AS Total_Room_Count,
    ROUND(COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB), 2) AS Occupancy_Rate_Percent
FROM tbl_otels o
JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
WHERE r.STATE = 'Realized'
GROUP BY o.OTEL_ID, o.OTEL_NAME, YEAR(r.check_in_date), MONTH(r.check_in_date)
ORDER BY o.OTEL_ID, Year, Month;

-- Last-Minute Booking Ratio (Reservations made within 3 days before check-in)

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    COUNT(r.RESERVATION_ID) AS Total_Reservations,
    SUM(
        CASE
            WHEN DATEDIFF(r.check_in_date, r.created_at) <= 3 THEN 1
            ELSE 0
        END
    ) AS Last_Minute_Reservations,
    ROUND(
        SUM(
            CASE
                WHEN DATEDIFF(r.check_in_date, r.created_at) <= 3 THEN 1
                ELSE 0
            END
        ) * 100.0 / COUNT(r.RESERVATION_ID),
        2
    ) AS Last_Minute_Rate_Percent
FROM tbl_otels o
JOIN tbl_reservations r ON r.OTEL_ID = o.OTEL_ID
WHERE r.STATE = 'Realized'
GROUP BY o.OTEL_ID, o.OTEL_NAME
ORDER BY Last_Minute_Rate_Percent DESC;

-- Reservation Cancellation Rate and Its Relationship with Price

WITH MonthlyData AS (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        DATE_FORMAT(r.CHECK_IN_DATE, '%Y-%m') AS Month,
        AVG(rp.TOTAL_PRICE) AS Average_Price,
        COUNT(DISTINCT r.RESERVATION_ID) AS Total_Reservations,
        SUM(
            CASE
                WHEN r.STATE IN ('CancelledByC', 'CancelledByH', 'Rejected', 'RejectedA')
                THEN 1 ELSE 0
            END
        ) AS Cancelled_Count,
        ROUND(
            SUM(
                CASE
                    WHEN r.STATE IN ('CancelledByC', 'CancelledByH', 'Rejected', 'RejectedA')
                    THEN 1 ELSE 0
                END
            ) * 100.0 / COUNT(DISTINCT r.RESERVATION_ID),
            2
        ) AS Cancellation_Rate
    FROM tbl_otels o
    JOIN tbl_room_types rt ON o.OTEL_ID = rt.OTEL_ID
    JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
    JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
    JOIN tbl_reservation_room_prices rp ON rp.RES_ROOMS_ID = rr.RES_ROOMS_ID
    GROUP BY o.OTEL_ID, o.OTEL_NAME, DATE_FORMAT(r.CHECK_IN_DATE, '%Y-%m')
),

TrendAnalysis AS (
    SELECT
        *,
        LAG(Average_Price) OVER (PARTITION BY OTEL_ID ORDER BY Month) AS Previous_Month_Price,
        LAG(Cancellation_Rate) OVER (PARTITION BY OTEL_ID ORDER BY Month) AS Previous_Month_Cancel_Rate
    FROM MonthlyData
),

ChangeCalc AS (
    SELECT
        OTEL_ID,
        OTEL_NAME,
        Month,
        Average_Price,
        Cancellation_Rate,
        ROUND((Average_Price - Previous_Month_Price) / Previous_Month_Price * 100, 2) AS Price_Change_Percent,
        ROUND((Cancellation_Rate - Previous_Month_Cancel_Rate) / Previous_Month_Cancel_Rate * 100, 2) AS Cancel_Change_Percent,
        CASE
            WHEN (Average_Price - Previous_Month_Price) > 0 AND (Cancellation_Rate - Previous_Month_Cancel_Rate) > 0 
                THEN 'Positive Relationship (Price ↑ → Cancellations ↑)'
            WHEN (Average_Price - Previous_Month_Price) < 0 AND (Cancellation_Rate - Previous_Month_Cancel_Rate) < 0 
                THEN 'Positive Relationship (Price ↓ → Cancellations ↓)'
            WHEN (Average_Price - Previous_Month_Price) > 0 AND (Cancellation_Rate - Previous_Month_Cancel_Rate) < 0 
                THEN 'Negative Relationship (Price ↑ → Cancellations ↓)'
            WHEN (Average_Price - Previous_Month_Price) < 0 AND (Cancellation_Rate - Previous_Month_Cancel_Rate) > 0 
                THEN 'Negative Relationship (Price ↓ → Cancellations ↑)'
            ELSE 'No Data / Stable'
        END AS Price_Cancel_Relationship
    FROM TrendAnalysis
)

SELECT
    OTEL_ID,
    OTEL_NAME,
    Month,
    Average_Price,
    Cancellation_Rate,
    Price_Change_Percent,
    Cancel_Change_Percent,
    Price_Cancel_Relationship
FROM ChangeCalc
ORDER BY OTEL_ID, Month;

-- Price Elasticity of Demand: Relationship between room price (ADR) and sold rooms

WITH PriceDemand AS (
    SELECT
        rt.ROOM_TYPE_ID,
        DATE(r.check_in_date) AS Date,
        COUNT(rr.RES_ROOMS_ID) AS Sold_Rooms,
        ROUND(SUM(rp.TOTAL_PRICE) / COUNT(rr.RES_ROOMS_ID), 2) AS ADR
    FROM tbl_room_types rt
    JOIN tbl_reservation_rooms rr ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
    JOIN tbl_reservations r ON r.RESERVATION_ID = rr.RESERVATION_ID
    JOIN tbl_reservation_room_prices rp ON rp.RES_ROOMS_ID = rr.RES_ROOMS_ID
    WHERE r.STATE = 'Realized'
    GROUP BY rt.ROOM_TYPE_ID, DATE(r.check_in_date)
)

SELECT
    Date,
    ADR,
    Sold_Rooms,
    LAG(ADR) OVER(PARTITION BY ROOM_TYPE_ID ORDER BY Date) AS Previous_ADR,
    LAG(Sold_Rooms) OVER(PARTITION BY ROOM_TYPE_ID ORDER BY Date) AS Previous_Sold_Rooms,

    -- Percentage change in demand (number of rooms sold)
    ROUND(
        ((Sold_Rooms - LAG(Sold_Rooms) OVER(PARTITION BY ROOM_TYPE_ID ORDER BY Date))
        / LAG(Sold_Rooms) OVER(PARTITION BY ROOM_TYPE_ID ORDER BY Date) * 100), 2
    ) AS Demand_Change_Percent,

    -- Percentage change in price (ADR)
    ROUND(
        ((ADR - LAG(ADR) OVER(PARTITION BY ROOM_TYPE_ID ORDER BY Date))
        / LAG(ADR) OVER(PARTITION_BY ROOM_TYPE_ID ORDER BY Date) * 100), 2
    ) AS Price_Change_Percent,

    -- Price elasticity of demand calculation
    ROUND(
        ((Sold_Rooms - LAG(Sold_Rooms) OVER(PARTITION_BY ROOM_TYPE_ID ORDER BY Date))
        / LAG(Sold_Rooms) OVER(PARTITION_BY ROOM_TYPE_ID ORDER BY Date)) /
        ((ADR - LAG(ADR) OVER(PARTITION_BY ROOM_TYPE_ID ORDER BY Date))
        / LAG(ADR) OVER(PARTITION_BY ROOM_TYPE_ID ORDER BY Date)), 2
    ) AS Price_Elasticity

FROM PriceDemand
ORDER BY ROOM_TYPE_ID, Date;

-- Reservation Source Distribution by Hotel (OTA vs Direct Channels)

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    CASE
        WHEN ref.REFERER_NAME LIKE '%booking%' THEN 'Booking.com (OTA)'
        WHEN ref.REFERER_NAME LIKE '%expedia%' THEN 'Expedia (OTA)'
        WHEN ref.REFERER_NAME LIKE '%tripadvisor%' THEN 'TripAdvisor (OTA)'
        WHEN ref.REFERER_NAME LIKE '%reseliva%' THEN 'Website (Direct)'
        WHEN ref.REFERER_NAME IS NULL THEN 'Other'
        ELSE 'Other OTA'
    END AS Reservation_Source,
    COUNT(DISTINCT r.RESERVATION_ID) AS Reservation_Count,
    ROUND(
        COUNT(DISTINCT r.RESERVATION_ID) * 100.0 /
        SUM(COUNT(DISTINCT r.RESERVATION_ID)) OVER (PARTITION BY o.OTEL_ID),
        2
    ) AS Percentage_Share
FROM tbl_reservations r
JOIN tbl_otels o ON o.OTEL_ID = r.OTEL_ID
LEFT JOIN tbl_reseliva_referers ref ON ref.REFERER_ID = r.REFERER_ID
GROUP BY o.OTEL_ID, o.OTEL_NAME, Reservation_Source
ORDER BY o.OTEL_ID, Percentage_Share DESC;

-- Country / City-Based Occupancy and Reservation Distribution

SELECT
    c.COUNTRY_NAME,
    ci.CITY_NAME,
    COUNT(DISTINCT r.RESERVATION_ID) AS Total_Reservations,
    COUNT(DISTINCT rr.RES_ROOMS_ID) AS Occupied_Rooms,
    SUM(rt.MAX_AVAB) AS Total_Rooms,
    ROUND(
        COUNT(DISTINCT rr.RES_ROOMS_ID) * 100.0 / SUM(rt.MAX_AVAB),
        2
    ) AS Occupancy_Rate_Percent
FROM tbl_reservations r
JOIN tbl_reservation_rooms rr ON rr.RESERVATION_ID = r.RESERVATION_ID
JOIN tbl_room_types rt ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
JOIN tbl_otels o ON o.OTEL_ID = r.OTEL_ID
JOIN tbl_cities ci ON ci.CITY_ID = o.CITY_ID
JOIN tbl_countries c ON c.COUNTRY_ID = ci.COUNTRY_ID
WHERE r.STATE IN ('Realized', 'Approved')
GROUP BY c.COUNTRY_NAME, ci.CITY_NAME
ORDER BY c.COUNTRY_NAME, ci.CITY_NAME
LIMIT 5;

-- Age Group and Travel Type Distribution (Family / Couple / Solo Travelers)

SELECT
    CASE
        WHEN FLOOR(DATEDIFF(r.CHECK_IN_DATE, m.BIRTH_DATE) / 365) < 18 THEN '0-17'
        WHEN FLOOR(DATEDIFF(r.CHECK_IN_DATE, m.BIRTH_DATE) / 365) BETWEEN 18 AND 30 THEN '18-30'
        WHEN FLOOR(DATEDIFF(r.CHECK_IN_DATE, m.BIRTH_DATE) / 365) BETWEEN 31 AND 50 THEN '31-50'
        ELSE '51+'
    END AS Age_Group,

    CASE
        WHEN rt.NUM_ADULT_LIMIT = 1 THEN 'Solo'
        WHEN rt.NUM_ADULT_LIMIT = 2 AND rt.NUM_CHILDREN_LIMIT = 0 THEN 'Couple'
        ELSE 'Family'
    END AS Travel_Type,

    COUNT(DISTINCT r.RESERVATION_ID) AS Total_Reservations,

    ROUND(
        COUNT(DISTINCT r.RESERVATION_ID) * 100.0 /
        SUM(COUNT(DISTINCT r.RESERVATION_ID)) OVER (),
        2
    ) AS Percentage_Share

FROM tbl_reservations r
JOIN tbl_members m ON m.MEMBER_ID = r.MEMBER_ID
JOIN tbl_reservation_rooms rr ON rr.RESERVATION_ID = r.RESERVATION_ID
JOIN tbl_room_types rt ON rt.ROOM_TYPE_ID = rr.ROOM_TYPE_ID
WHERE r.STATE IN ('Realized', 'Approved')
GROUP BY Age_Group, Travel_Type
ORDER BY Age_Group, Travel_Type;

-- High Cancellation Tendency Guest Profiles
-- This query analyzes guests by their cancellation rate
-- and groups them into risk levels (High, Medium, Low)
-- based on their historical reservation behavior.

WITH GuestCancellation AS (
    SELECT
        m.MEMBER_ID,
        m.COUNTRY_ID,
        COUNT(DISTINCT r.RESERVATION_ID) AS Total_Reservations,
        SUM(
            CASE
                WHEN r.STATE IN ('CancelledByC', 'CancelledByH', 'Rejected', 'RejectedA')
                THEN 1 ELSE 0
            END
        ) AS Cancellations,
        ROUND(
            SUM(
                CASE
                    WHEN r.STATE IN ('CancelledByC', 'CancelledByH', 'Rejected', 'RejectedA')
                    THEN 1 ELSE 0
                END
            ) * 100.0 / COUNT(DISTINCT r.RESERVATION_ID),
            2
        ) AS Cancellation_Rate
    FROM tbl_reservations r
    JOIN tbl_members m ON m.MEMBER_ID = r.MEMBER_ID
    WHERE r.STATE IN ('CancelledByC', 'CancelledByH', 'Rejected', 'RejectedA', 'Realized', 'Approved')
    GROUP BY m.MEMBER_ID, m.COUNTRY_ID
)

SELECT
    c.COUNTRY_NAME,
    CASE
        WHEN gc.Cancellation_Rate >= 50 THEN 'High-Risk Guest Profile'
        WHEN gc.Cancellation_Rate BETWEEN 25 AND 49 THEN 'Medium-Risk Guest Profile'
        ELSE 'Low-Risk Guest Profile'
    END AS Cancellation_Tendency,
    ROUND(AVG(gc.Cancellation_Rate), 2) AS Avg_Cancellation_Rate,
    COUNT(DISTINCT gc.MEMBER_ID) AS Guest_Count
FROM GuestCancellation gc
LEFT JOIN tbl_countries c ON c.COUNTRY_ID = gc.COUNTRY_ID
GROUP BY c.COUNTRY_NAME, Cancellation_Tendency
ORDER BY Avg_Cancellation_Rate DESC;

-- New vs Returning Guest Ratio
-- This query analyzes guest loyalty by comparing
-- first-time (new) guests vs returning guests per hotel.

WITH FirstBooking AS (
    SELECT
        m.MEMBER_ID,
        MIN(r.CHECK_IN_DATE) AS First_Booking_Date
    FROM tbl_members m
    JOIN tbl_reservations r ON m.MEMBER_ID = r.MEMBER_ID
    WHERE r.STATE IN ('Realized', 'Approved')
    GROUP BY m.MEMBER_ID
),

GuestType AS (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        r.RESERVATION_ID,
        r.MEMBER_ID,
        CASE
            WHEN r.CHECK_IN_DATE = fb.First_Booking_Date THEN 'New Guest'
            ELSE 'Returning Guest'
        END AS Guest_Type
    FROM tbl_reservations r
    JOIN FirstBooking fb ON fb.MEMBER_ID = r.MEMBER_ID
    JOIN tbl_otels o ON o.OTEL_ID = r.OTEL_ID
    WHERE r.STATE IN ('Realized', 'Approved')
)

SELECT
    o.OTEL_ID,
    o.OTEL_NAME,
    SUM(CASE WHEN Guest_Type = 'New Guest' THEN 1 ELSE 0 END) AS New_Guest_Count,
    SUM(CASE WHEN Guest_Type = 'Returning Guest' THEN 1 ELSE 0 END) AS Returning_Guest_Count,
    COUNT(*) AS Total_Guests,
    ROUND(SUM(CASE WHEN Guest_Type = 'New Guest' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS New_Guest_Percentage,
    ROUND(SUM(CASE WHEN Guest_Type = 'Returning Guest' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Returning_Guest_Percentage
FROM GuestType o
GROUP BY o.OTEL_ID, o.OTEL_NAME
ORDER BY o.OTEL_ID
LIMIT 5;

-- Customer Satisfaction Analysis
-- This query analyzes hotel-level customer satisfaction scores
-- by aggregating average ratings across key review dimensions:
-- cleanliness, location, service, and value-for-money.

WITH ReviewScores AS (
    SELECT
        r.RESERVATION_ID,
        o.OTEL_ID,
        o.OTEL_NAME,
        rev.REVIEW_ID,
        rev.CLEANLINESS AS Cleanliness_Score,
        rev.LOCATION AS Location_Score,
        rev.SERVICE AS Service_Score,
        rev.VALUE AS ValueForMoney_Score,
        ROUND((rev.CLEANLINESS + rev.LOCATION + rev.SERVICE + rev.VALUE) / 4, 2) AS Avg_Score
    FROM tbl_review rev
    JOIN tbl_reservations r ON r.RESERVATION_ID = rev.RESERVATION_ID
    JOIN tbl_otels o ON o.OTEL_ID = r.OTEL_ID
    WHERE r.STATE IN ('Realized', 'Approved')
),

SatisfactionAnalysis AS (
    SELECT
        o.OTEL_ID,
        o.OTEL_NAME,
        AVG(rs.Avg_Score) AS Overall_Satisfaction_Score,
        AVG(rs.Cleanliness_Score) AS Avg_Cleanliness,
        AVG(rs.Location_Score) AS Avg_Location,
        AVG(rs.Service_Score) AS Avg_Service,
        AVG(rs.ValueForMoney_Score) AS Avg_ValueForMoney,
        COUNT(DISTINCT rs.REVIEW_ID) AS Total_Reviews
    FROM ReviewScores rs
    JOIN tbl_otels o ON o.OTEL_ID = rs.OTEL_ID
    GROUP BY o.OTEL_ID, o.OTEL_NAME
)

SELECT
    OTEL_ID,
    OTEL_NAME,
    ROUND(Overall_Satisfaction_Score, 2) AS Overall_Score,
    ROUND(Avg_Cleanliness, 2) AS Cleanliness,
    ROUND(Avg_Location, 2) AS Location,
    ROUND(Avg_Service, 2) AS Service,
    ROUND(Avg_ValueForMoney, 2) AS ValueForMoney,
    CASE
        WHEN Overall_Satisfaction_Score >= 8 THEN 'Very Satisfied'
        WHEN Overall_Satisfaction_Score BETWEEN 6 AND 7.99 THEN 'Satisfied'
        WHEN Overall_Satisfaction_Score BETWEEN 4 AND 5.99 THEN 'Neutral'
        ELSE 'Unsatisfied'
    END AS Satisfaction_Level,
    Total_Reviews
FROM SatisfactionAnalysis
ORDER BY Overall_Score DESC
LIMIT 10;