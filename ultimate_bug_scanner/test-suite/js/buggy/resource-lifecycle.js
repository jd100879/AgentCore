// Resource lifecycle regression sample
const notifier = {
  start() {
    document.addEventListener('visibilitychange', () => {
      console.log('changed');
    });
    const timerId = setInterval(() => console.log('tick'), 1000);
    this.timerId = timerId;
  }
};

notifier.start();

const observer = new MutationObserver(() => {});
observer.observe(document.body, { childList: true });
// missing removeEventListener, clearInterval, disconnect
