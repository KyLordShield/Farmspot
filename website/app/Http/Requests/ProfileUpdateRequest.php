<?php

namespace App\Http\Requests;

use App\Rules\PersonName;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ProfileUpdateRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        PersonName::normalize($this, 'name');
        if (is_string($this->input('email'))) {
            $this->merge(['email' => strtolower(trim($this->input('email')))]);
        }
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'name' => ['bail', 'required', 'string', 'max:'.PersonName::MAX_LENGTH, new PersonName],
            'phone' => ['nullable', 'string', 'regex:/^09[0-9]{9}$/D',
                Rule::unique('user', 'USR_MOBILE_NUMBER')->ignore($this->user()->getKey(), 'USR_ID')],
            'email' => [
                'required',
                'string',
                'lowercase',
                'email',
                'max:200',
                // The reset-code destination cannot be changed through this
                // older profile endpoint to bypass email verification.
                Rule::in([strtolower($this->user()->USR_EMAIL)]),
                Rule::unique('user', 'USR_EMAIL')->ignore($this->user()->getKey(), 'USR_ID'),
            ],
        ];
    }

    public function messages(): array
    {
        return [
            'email.in' => 'For security, your administrator email cannot be changed here.',
            'phone.regex' => 'Enter an 11-digit mobile number starting with 09.',
            'phone.unique' => 'This mobile number is already in use.',
        ];
    }
}
