local multi, thread = require("multi"):init()
conn1 = multi:newConnection()
conn2 = multi:newConnection();

((conn1 * conn2))(function() print("Triggered!") end)

conn1:Fire()
conn2:Fire()

-- Looks like this is trigering a response. It shouldn't. We need to account for this
conn1:Fire()
conn1:Fire()
