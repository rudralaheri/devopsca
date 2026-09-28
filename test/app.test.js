const request = require('supertest');
const app = require('../src/app');

describe('API Tests', () => {
    it('GET /health returns 200', async () => {
        const res = await request(app).get('/health');
        expect(res.statusCode).toEqual(200);
        expect(res.body).toEqual({ status: 'ok' });
    });

    it('GET /api/tasks returns 200 and an array', async () => {
        const res = await request(app).get('/api/tasks');
        expect(res.statusCode).toEqual(200);
        expect(Array.isArray(res.body)).toBeTruthy();
    });

    it('GET /api/tasks/:id with valid ID returns 200', async () => {
        const res = await request(app).get('/api/tasks/1');
        expect(res.statusCode).toEqual(200);
        expect(res.body.id).toEqual(1);
    });

    it('GET /api/tasks/:id with invalid ID returns 404', async () => {
        const res = await request(app).get('/api/tasks/999');
        expect(res.statusCode).toEqual(404);
    });

    it('POST /api/tasks creates a task', async () => {
        const res = await request(app)
            .post('/api/tasks')
            .send({ title: 'New Task' });
        expect(res.statusCode).toEqual(201);
        expect(res.body.title).toEqual('New Task');
        expect(res.body.id).toBeDefined();
    });

    it('POST /api/tasks with missing title returns 400', async () => {
        const res = await request(app)
            .post('/api/tasks')
            .send({});
        expect(res.statusCode).toEqual(400);
    });

    it('POST /api/tasks with empty title returns 400', async () => {
        const res = await request(app)
            .post('/api/tasks')
            .send({ title: '   ' });
        expect(res.statusCode).toEqual(400);
    });
});
