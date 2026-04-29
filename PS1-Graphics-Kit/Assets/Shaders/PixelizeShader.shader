Shader "Hidden/Custom/Pixelize"
{
    Properties
    {
        // Теперь задаем виртуальную высоту экрана (например, 240, 360, 480)
        _VirtualResolution ("Virtual Height Resolution", Float) = 240
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "Pixelize"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _VirtualResolution;

            half4 Frag (Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // 1. Вычисляем масштаб: сколько реальных пикселей в одном виртуальном.
                // Делим высоту экрана на желаемое разрешение.
                float rawScale = _ScreenParams.y / _VirtualResolution;
                
                // 2. МАГИЯ ЗДЕСЬ: Округляем масштаб до целого числа (floor или round).
                // Используем max(1.0, ...), чтобы масштаб никогда не был равен 0.
                float scale = max(1.0, floor(rawScale));

                // 3. Вычисляем финальную сетку, разделив реальный экран на наш целый масштаб.
                // Теперь сетка всегда будет состоять из ИДЕАЛЬНО ровных квадратов.
                float2 pixels = floor(_ScreenParams.xy / scale);
                
                // 4. Стандартная пикселизация
                uv = floor(uv * pixels) / pixels;

                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
                return color;
            }
            ENDHLSL
        }
    }
}
