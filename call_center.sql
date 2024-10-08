/* For this dataset I asked to ChatGPT the following:
create a downloadable csv dataset with 500 rows of call center company so I can perform some data analysis and cleaning.
Please include some null, values, duplicated and all of this in a time frame of 1 month, 
beside that, create another csv dataset called : agent and assign a random first_name, last_name to the Agent_ID? */

-- Data Cleaning

-- Check for duplicate

WITH duplicate_cte AS (
	SELECT *,
	ROW_NUMBER() OVER(
    PARTITION BY call_id, agent_id, customer_id, call_duration, call_date, issue_resolved, call_result, issue_type) AS row_num
	FROM call_center)
SELECT * 
FROM duplicate_cte
WHERE row_num > 1;

-- Created a new table and added a new column to clean and mantein the original file untouched.

CREATE TABLE call_center2 (
  `Call_ID` int DEFAULT NULL,
  `Agent_ID` int DEFAULT NULL,
  `Customer_ID` int DEFAULT NULL,
  `Call_Duration` double DEFAULT NULL,
  `Call_Date` text,
  `Issue_Resolved` text,
  `Call_Result` text,
  `Issue_Type` text,
  `row_num` INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Inserted the data from the original file.

INSERT INTO call_center2
SELECT *,
	ROW_NUMBER() OVER(
    PARTITION BY call_id, agent_id, customer_id, call_duration, call_date, issue_resolved, call_result, issue_type) AS row_num
FROM call_center;

-- Delected duplicated values
DELETE 
FROM call_center2
WHERE row_num > 1;

SELECT *  
FROM call_center2;

-- Standardize the data

SELECT CONCAT(UPPER(LEFT(call_result,1)),LOWER(SUBSTRING(call_result,2))) AS call_result
FROM call_center2;

UPDATE call_center2
SET call_result = CONCAT(UPPER(LEFT(call_result,1)),LOWER(SUBSTRING(call_result,2)));

SELECT CONCAT(UPPER(LEFT(issue_type,1)),LOWER(SUBSTRING(issue_type,2))) AS issue_type
FROM call_center2;

UPDATE call_center2
SET issue_type = CONCAT(UPPER(LEFT(issue_type,1)),LOWER(SUBSTRING(issue_type,2)));

SELECT * 
FROM call_center2
WHERE issue_type LIKE 'Product%';

UPDATE call_center2
SET issue_type = 'Inquiry'
WHERE issue_type LIKE 'Product%';

SELECT * 
FROM call_center2
WHERE issue_type LIKE 'Technical%';

UPDATE call_center2
SET issue_type = 'Technical'
WHERE issue_type LIKE 'Technical%';

-- Considering that all the empty tables on 'Issue_resolved' were Escalated, we can assume this is still waiting for reply
-- therefore this is going to be updated as Pending

SELECT Issue_Resolved, Call_Result
FROM call_center2
WHERE Issue_Resolved ='';

UPDATE call_center2
SET Issue_Resolved = 'Pending'
WHERE Issue_Resolved ='';

SELECT *
FROM call_center2;

ALTER TABLE call_center2 
DROP COLUMN row_num;

-- I verified the agent table has no duplicate;
WITH agent_cte AS (
SELECT * , 
	ROW_NUMBER() OVER(PARTITION BY agent_id, first_name, last_name) AS row_num
FROM agent_data)
SELECT *
FROM agent_cte
WHERE row_num > 1;

/* For the EDA process I asked once again to ChatGPT:
"as a stakeholder what kind of question do I need to check"
I will add the question ChatGPT generated before any query. */

-- 1. Operational Efficiency - How long do calls last?
-- 1.1 Average call duration: Are calls taking too long to resolve? 
	-- Answer: The average for call is 30min and the resolved cases are taking the same amoung of time.
    
SELECT ROUND(AVG(Call_Duration),2) AS avg_call_duration
FROM call_center2;

SELECT 
	call_result,
    ROUND(AVG(Call_Duration),2) AS avg_call_duration,
    COUNT(*) AS total_calls
FROM call_center2
GROUP BY Call_Result;

-- 1.2 Distribution of call durations: Are there outliers or frequent short/long calls?
	-- Answer: There isnt any outliers, only frequent short and long calls
    
SELECT 
	agent_id,
    call_duration,
    call_result
FROM call_center2
WHERE call_duration > (
        SELECT AVG(Call_Duration) + 2 *STD(Call_Duration) 
        FROM call_center2);

-- 1.3 What is the call resolution rate?
	-- Answer: Escalated: 7.71%, Resolved: 60.31% and Unresolved: 31.98%
    
WITH total_call_cte AS (
	SELECT COUNT(*) AS total_calls
	FROM call_center2
    ),
	resolution_count_cte AS (
	SELECT call_result,COUNT(call_result) AS total_call_result
	FROM call_center2
    GROUP BY call_result
    )
SELECT call_result, ROUND(total_call_result/total_calls * 100,2) AS avg_resolution
FROM total_call_cte, resolution_count_cte;

-- Call escalations: What percentage of calls get escalated? Are certain issues more likely to lead to escalations?
	-- Answer: Complaint call type suffer the higher escalations
    
WITH total_call_cte AS (
	SELECT COUNT(*) AS total_calls
	FROM call_center2
    ),	
    escalated_cte AS (
    SELECT issue_type, COUNT(call_result) AS escalated_calls
FROM call_center2
WHERE call_result = 'Escalated'
GROUP BY issue_type
)
SELECT issue_type, ROUND(escalated_calls/total_calls *100,2) AS avg_escalated_type
FROM total_call_cte, escalated_cte;

-- 2. Agent Performance - Which agents are resolving issues the fastest?
	-- 2.1 Identify top performers based on call resolution time and frequency of resolved calls
	-- Answer: Judith Salazar was the agent who resolved her call in the shortest time but in this time frame she handle only one.
    -- Dwayne Burke was the fastest one with 9 calls
    
SELECT 	call_center2.agent_id,
		SUM(Call_Duration) AS call_duration,
        COUNT(*) AS call_count,
		agent_data.first_name,
		agent_data.last_name,
        RANK() OVER (ORDER BY SUM(Call_Duration) ASC) AS total_call_duration,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS num_call
FROM call_center2
LEFT JOIN agent_data 
	ON call_center2.agent_id = agent_data.agent_id
WHERE call_center2.Call_Result LIKE 'Resolved'
GROUP BY call_center2.agent_id,agent_data.first_name,agent_data.last_name;

-- 3. Customer Experience - What are common customer issues?
	-- 3.1 Issue_Type analysis: Are billing or complaints the most frequent issues? Are they increasing over time?
	-- Answer: Complaints are the most billing frequent calls followed by billing, tech and inquiry.
SELECT Issue_Type,
		COUNT(*)
FROM call_center2
GROUP BY Issue_Type;

-- With this query we can see the total call_type by date, as an extra I ranked the type by day.
SELECT 
	issue_type,
	DATE(Call_Date) AS date_call,
    COUNT(*) AS total_call,
    RANK() OVER(PARTITION BY DATE(Call_Date) ORDER BY COUNT(*) DESC) rank_type_date
FROM call_center2
GROUP BY issue_type, date_call
ORDER BY date_call;

-- Peak Call Times - When is the call center busiest?
	-- Analyze call volume over time to identify peak hours and days. Are certain issue types more frequent at specific times?
	-- Answer: The peak hour is 3am where most type are Complaint and Saturday were the busiest day where most type are Complaint as well
    
SELECT COUNT(*) AS total_calls,
	issue_type,
	TIME(Call_Date) AS time_calls
FROM call_center2
GROUP BY time_calls, issue_type
ORDER BY total_calls DESC;

SELECT COUNT(*) AS total_calls,
	issue_type,
	DAYNAME(Call_Date) AS day_of_calls
FROM call_center2
GROUP BY day_of_calls,issue_type
ORDER BY total_calls DESC;