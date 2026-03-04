browser.contextMenus.create({
  id: "send-to-fetchix",
  title: "Send to Fetchix",
  contexts: ["link"]
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "send-to-fetchix") {
    let targetUrl = "fetchix://" + info.linkUrl;
    browser.tabs.update({ url: targetUrl });
  }
});

