// Test fixture: floating promise (.then without .catch)
function badFunction() {
    fetchData().then(data => {
        console.log(data);
    });
    // Missing .catch() - rejections silently lost!
}
