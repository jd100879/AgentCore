// CLEAN JS security sample
async function runUserCode(token) {
  const allowed = new Set(['PING']);
  if (!allowed.has(token)) throw new Error('invalid');
  return 'ok';
}

function render(comment) {
  const node = document.getElementById('box');
  if (node) {
    node.textContent = comment;
  }
}

async function fetchData(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error('bad response');
  return response.json();
}
