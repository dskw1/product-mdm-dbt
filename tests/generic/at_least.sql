{% test at_least(model, column_name, threshold) %}
-- Fails when any row of the column falls below the threshold.
select {{ column_name }} as value
from {{ model }}
where {{ column_name }} is null or {{ column_name }} < {{ threshold }}
{% endtest %}
