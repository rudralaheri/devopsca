const express = require('express');
const app = express();
app.use(express.json());

let tasks = [
    { id: 1, title: 'Learn DevSecOps' },
    { id: 2, title: 'Implement Zero-Trust Pipeline' }
];
let nextId = 3;

app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
});

app.get('/api/tasks', (req, res) => {
    res.status(200).json(tasks);
});

app.get('/api/tasks/:id', (req, res) => {
    const task = tasks.find(t => t.id === parseInt(req.params.id));
    if (!task) return res.status(404).json({ error: 'Task not found' });
    res.status(200).json(task);
});

app.post('/api/tasks', (req, res) => {
    const { title } = req.body;
    if (!title || title.trim() === '') {
        return res.status(400).json({ error: 'Title is required' });
    }
    const newTask = { id: nextId++, title: title.trim() };
    tasks.push(newTask);
    res.status(201).json(newTask);
});

// Export for testing
module.exports = app;

if (require.main === module) {
    const port = process.env.PORT || 3000;
    app.listen(port, () => {
        console.log(`Server running on port ${port}`);
    });
}
