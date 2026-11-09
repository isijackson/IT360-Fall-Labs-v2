const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('<h1>Canyon Youth Soccer — Fall Schedule</h1><p>Saturday games at Flat Iron Mesa Park, 9:00 and 10:30.</p>'));
app.listen(process.env.PORT || 3000, () => console.log('Schedule site running'));
