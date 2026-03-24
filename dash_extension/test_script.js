const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();
  await page.goto('http://localhost:8000/index.html');
  
  // Select type A
  await page.select('#svcExecRecipientTyCd', 'A');
  
  // Wait for options to populate
  await new Promise(r => setTimeout(r, 200));
  
  // Select option value '1'
  await page.select('#svcExecRecipientId', '1');
  
  // Try to click the + button to see if the DOM updates
  await page.evaluate(() => {
    const addBtn = document.querySelector('a[href*="fnAddRecipient"]');
    addBtn.click();
  });
  
  // Check if item was added
  const text = await page.evaluate(() => {
    return document.getElementById('recipientTyId_view').innerHTML;
  });
  console.log('Result HTML after click():', text);
  
  await browser.close();
})();
