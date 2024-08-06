error_log /dev/stdout info;
lua_shared_dict my_dict 1m;

init_by_lua_block {
   -- Initialize a shared dictionary to store the random Fibonacci input
   local dict = ngx.shared.my_dict
   -- Seed the random number generator
   math.randomseed(os.time() + ngx.worker.pid())
   -- Generate a random number (could adjust the range as needed, here we choose between 20 and 30)
   local random_fib_n = math.random(25, 29)
   -- Store the random number in the shared dictionary
   dict:set("fib_n", random_fib_n)
   -- Log the selected random_fib_n value at initialization
   ngx.log(ngx.INFO, "Initialized with random_fib_n: " .. random_fib_n)             
}      
server {
   listen       80;
   server_name  localhost;

   location / {
       default_type 'text/plain';
       content_by_lua_block {
         -- Function to calculate Fibonacci
         local function fib(n)
             if n<2 then return n end
             return fib(n-1)+fib(n-2)
         end

         -- Fetch the Fibonacci input from the shared dictionary
         local dict = ngx.shared.my_dict
         local n = dict:get("fib_n")
         -- Compute the Fibonacci number
         local fib_number = fib(n)
         -- Output the result
         ngx.say(fib_number)
         ngx.say(n)
         -- Log the Fibonacci number and the value of n
         ngx.log(ngx.INFO, "This nginx calculated fibonacci number for n=" .. n)
       }
   }

   error_page   500 502 503 504  /50x.html;
   location = /50x.html {
       root   /usr/share/nginx/html;
   }
}
