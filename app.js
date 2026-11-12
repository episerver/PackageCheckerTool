(() => {
  const toast = document.getElementById('toast');
  const depsInput = document.getElementById('deps-path');
  const customCode = document.querySelector('#custom-command code');
  let toastTimer;

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 1800);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
    } catch (_) {
      const area = document.createElement('textarea');
      area.value = text;
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      document.execCommand('copy');
      area.remove();
    }
    showToast('Command copied');
  }

  function shellQuote(value) {
    return `'${String(value).replace(/'/g, `'"'"'`)}'`;
  }

  function updateCustomCommand() {
    const path = depsInput.value.trim() || '/home/site/wwwroot/MyApp.deps.json';
    customCode.textContent = `bash /home/site/wwwroot/nugetchk.sh --deps ${shellQuote(path)} 2>&1 | tee /home/site/wwwroot/nugetchk_terminal_report.txt`;
  }

  document.querySelectorAll('.copy-command').forEach((button) => {
    button.addEventListener('click', () => copyText(button.dataset.command));
  });

  document.getElementById('copy-custom').addEventListener('click', () => copyText(customCode.textContent));
  depsInput.addEventListener('input', updateCustomCommand);
  updateCustomCommand();
})();
