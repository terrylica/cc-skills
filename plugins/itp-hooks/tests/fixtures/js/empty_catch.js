// Test fixture: empty catch block
async function badFunction() {
    try {
        await riskyOperation();
    } catch (e) {}
}
