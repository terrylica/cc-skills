// Test fixture: GOOD JS code (should pass)
async function goodFunction() {
    try {
        await riskyOperation();
    } catch (e) {
        console.error('Operation failed:', e);
        throw e;
    }
}

function goodPromise() {
    fetchData()
        .then(data => console.log(data))
        .catch(err => console.error('Fetch failed:', err));
}
