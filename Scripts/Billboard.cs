using UnityEngine;
using UnityEngine.Rendering.Universal; // Required for DecalProjector

public class Billboard : MonoBehaviour
{
    [Header("Billboard Settings")]
    [Tooltip("The target to face. If null and 'Use Main Camera' is true, it will face the Camera.main")]
    public Transform target;
    [Tooltip("If true, the object will always face the main camera")]
    public bool useMainCamera = true;
    [Tooltip("If true, the object will only rotate around the Y axis (vertical)")]
    public bool lockYAxis = true;
    [Tooltip("If true, the billboard will slightly tilt towards the camera when viewed from above")]
    public bool allowVerticalTilt = true;
    [Tooltip("How much the billboard tilts towards the camera (0.01 is a very subtle effect)")]
    [Range(0f, 1f)]
    public float verticalTilt = 0.01f;
    [Tooltip("Maximum tilt angle in degrees")]
    public float maxTiltAngle = 10f;

    [Header("Shadow Settings")]
    [Tooltip("If true, a shadow will be projected onto the ground")]
    public bool showShadow = false;
    
    [Tooltip("The Decal Projector component (BEST for hills/slopes). Requires Decal feature in URP Renderer.")]
    public DecalProjector shadowProjector;
    
    [Tooltip("Alternative: Simple object for shadow (e.g. Quad). Looks 'paper-like' on hills.")]
    public Transform simpleShadowObject;

    [Tooltip("Layer mask for the ground to project the shadow on")]
    public LayerMask groundLayer;
    [Tooltip("Maximum distance to search for ground")]
    public float maxShadowDistance = 5f;
    [Tooltip("Offset above the pivot to start the raycast (helps when pivot is at feet level)")]
    public float raycastOffset = 0.5f;

    [Header("Shadow Polish")]
    [Tooltip("If true, the shadow will fade and change size based on height")]
    public bool dynamicShadow = true;
    [Tooltip("Base size of the shadow")]
    public float baseSize = 1f;
    [Tooltip("Minimum transparency of the shadow when far from ground")]
    public float minAlpha = 0.2f;

    void LateUpdate()
    {
        // --- Billboard Logic ---
        HandleBillboard();

        // --- Shadow Logic ---
        HandleShadow();
    }

    private void HandleBillboard()
    {
        if (useMainCamera && target == null)
        {
            if (Camera.main != null)
                target = Camera.main.transform;
        }

        if (target != null)
        {
            // Используем инвертированное направление, чтобы избежать отзеркаливания
            Vector3 direction = transform.position - target.position; 
            if (direction == Vector3.zero) return;

            // 1. Считаем чисто вертикальный поворот (только по Y)
            Vector3 horizontalDir = new Vector3(direction.x, 0, direction.z);
            if (horizontalDir == Vector3.zero) horizontalDir = transform.forward;
            Quaternion verticalRotation = Quaternion.LookRotation(horizontalDir);

            if (lockYAxis && allowVerticalTilt)
            {
                // 2. Считаем полный поворот на камеру (сферический)
                Quaternion fullRotation = Quaternion.LookRotation(direction);
                
                // 3. Смешиваем их согласно verticalTilt
                Quaternion targetRotation = Quaternion.Slerp(verticalRotation, fullRotation, verticalTilt);
                
                // 4. Ограничиваем наклон в градусах
                Vector3 euler = targetRotation.eulerAngles;
                float angleX = euler.x;
                if (angleX > 180) angleX -= 360; 
                angleX = Mathf.Clamp(angleX, -maxTiltAngle, maxTiltAngle);
                
                transform.rotation = Quaternion.Euler(angleX, euler.y, euler.z);
            }
            else if (lockYAxis)
            {
                transform.rotation = verticalRotation;
            }
            else
            {
                transform.rotation = Quaternion.LookRotation(direction);
            }
        }
    }

    private void HandleShadow()
    {
        bool hasProjector = shadowProjector != null;
        bool hasSimple = simpleShadowObject != null;

        if (!hasProjector && !hasSimple) return;

        // Toggle objects based on settings
        if (hasProjector) shadowProjector.gameObject.SetActive(showShadow);
        if (hasSimple) simpleShadowObject.gameObject.SetActive(showShadow);

        if (showShadow)
        {
            RaycastHit hit;
            // Raycast starting from an offset above the pivot
            Vector3 rayStart = transform.position + Vector3.up * raycastOffset;
            
            if (Physics.Raycast(rayStart, Vector3.down, out hit, maxShadowDistance + raycastOffset, groundLayer))
            {
                // Calculate distance from the actual transform position, not the offset start
                float actualDistance = Vector3.Distance(transform.position, hit.point);
                float ratio = 1f - Mathf.Clamp01(actualDistance / maxShadowDistance);

                if (hasProjector)
                {
                    // Position projector slightly above the hit point
                    shadowProjector.transform.position = hit.point + Vector3.up * 0.5f;
                    
                    if (dynamicShadow)
                    {
                        // Fade based on distance
                        shadowProjector.fadeFactor = Mathf.Lerp(minAlpha, 1f, ratio);
                        // Scale based on distance
                        float sizeMult = Mathf.Lerp(1.5f, 1f, ratio);
                        shadowProjector.size = new Vector3(baseSize * sizeMult, baseSize * sizeMult, 1f);
                    }
                }

                if (hasSimple)
                {
                    // Simple object logic (legacy)
                    simpleShadowObject.position = hit.point + Vector3.up * 0.01f;
                    simpleShadowObject.rotation = Quaternion.FromToRotation(Vector3.up, hit.normal);
                    
                    if (dynamicShadow)
                    {
                        float sizeMult = Mathf.Lerp(1.5f, 1f, ratio);
                        simpleShadowObject.localScale = Vector3.one * baseSize * sizeMult;
                    }
                }
            }
            else
            {
                // Hide if ground is too far
                if (hasProjector) shadowProjector.gameObject.SetActive(false);
                if (hasSimple) simpleShadowObject.gameObject.SetActive(false);
            }
        }
    }
}
