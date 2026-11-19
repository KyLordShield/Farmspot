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
            'email' => [
                'required',
                'string',
                'lowercase',
                'email',
                'max:200',
                Rule::unique('user', 'USR_EMAIL')->ignore($this->user()->getKey(), 'USR_ID'),
            ],
        ];
    }
}
