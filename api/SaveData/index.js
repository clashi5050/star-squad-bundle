// POST /api/data -> upserts the signed-in user's app state document.
const { container, getUser } = require("../shared/store");

module.exports = async function (context, req) {
  const user = getUser(req);
  if (!user || !user.userId) {
    context.res = { status: 401, body: { error: "not signed in" } };
    return;
  }
  const data = req.body;
  if (data === undefined || data === null) {
    context.res = { status: 400, body: { error: "missing body" } };
    return;
  }
  const doc = {
    id: user.userId,
    userId: user.userId,
    userDetails: user.userDetails || null,
    data,
    updatedAt: new Date().toISOString()
  };
  try {
    await container.items.upsert(doc);
    context.res = { status: 200, body: { ok: true, updatedAt: doc.updatedAt } };
  } catch (e) {
    context.log.error("SaveData failed", e);
    context.res = { status: 500, body: { error: "save failed" } };
  }
};
