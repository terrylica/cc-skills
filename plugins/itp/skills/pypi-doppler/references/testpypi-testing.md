# TestPyPI Testing

To test the publishing workflow without affecting production:

1. **Get TestPyPI token**:
   - Visit: <https://test.pypi.org/manage/account/token/>
   - Create token

2. **Store in Doppler** (separate key):

   ```bash
   doppler secrets set TESTPYPI_TOKEN='your-test-token' \
     --project private-config \
     --config prd
   ```

3. **Modify publish script temporarily**:

   ```bash
   /usr/bin/env bash << 'DOPPLER_EOF_2'
   # In scripts/publish-to-pypi.sh, change
   uv publish --token "${PYPI_TOKEN}"

   # To
   TESTPYPI_TOKEN=$(doppler secrets get TESTPYPI_TOKEN --plain)
   uv publish --repository testpypi --token "${TESTPYPI_TOKEN}"
   DOPPLER_EOF_2
   ```

4. **Test publish**:

   ```bash
   ./scripts/publish-to-pypi.sh
   ```

5. **Verify on TestPyPI**:
   - <https://test.pypi.org/project/your-package/>

6. **Restore script** to production configuration
