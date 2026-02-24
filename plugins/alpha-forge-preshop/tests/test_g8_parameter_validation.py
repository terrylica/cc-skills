'''Tests for G8: Parameter Validation'''

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))

from gates.g8_parameter_validation import ParameterValidator, validate_parameters


def test_numeric_range_validation():
    '''Test numeric bounds validation.'''
    validator = ParameterValidator()
    
    # Valid: within range
    is_valid, error = validator.validate_numeric_range(5.0, min_val=0, max_val=10)
    assert is_valid and error is None
    
    # Invalid: below minimum
    is_valid, error = validator.validate_numeric_range(-1.0, min_val=0, max_val=10)
    assert not is_valid and error is not None


def test_enum_validation():
    '''Test enum membership validation.'''
    validator = ParameterValidator()
    allowed = ['bullish_only', 'not_bearish', 'any']
    
    # Valid: in enum
    is_valid, error = validator.validate_enum('bullish_only', allowed)
    assert is_valid and error is None


def test_validate_parameters_spec():
    '''Test parameter validation against specification.'''
    spec = {
        'atr_period': {
            'type': 'numeric',
            'min': 1,
            'max': 100,
        },
    }
    
    # Valid parameters
    params_valid = {'atr_period': 32}
    errors = validate_parameters(params_valid, spec)
    assert len(errors) == 0
