select
  urlencode('my special string''s & things?');

select
  content
from
  http_get (
    'https://postman-echo.com/get?foo1=bar1&foo2=bar2'
  );
