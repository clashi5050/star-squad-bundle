// GET /api/data -> returns the signed-in user's saved app state (or null).
const { container, getUser } = require("../shared/store");

module.exports = async function (context, req) {
  const user = getUser(req);
  if (!user || !user.userId) {
    context.res = { status: 401, body: { error: "not signed in" } };
    return;
  }
  try {
    const { resource } = await container.item(user.userId, user.userId).read();
    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: { data: resource ? resource.data : null, updatedAt: resource ? resource.updatedAt : null }
    };
  } catch (e) {
    if (e.code === 404) {
      context.res = { status: 200, body: { data: null } };
      return;
    }
    context.log.error("GetData failed", e);
    context.res = { status: 500, body: { error: "read failed" } };
  }
};
