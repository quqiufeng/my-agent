;; static_stdlib.scm — StaticPy 标准库
;; 默认包含: OpenBLAS, LAPACK, libTorch (aoti)
;; Python 风格包装: np.*, torch.*, la.*, ml.*
;;
;; 在 static_build.sh 中自动并入每个编译

(import (chezscheme))

;; ============================================================
;; Part 1: OpenBLAS (numpy 底层) — 可选加载，不可用时跳过
;; ============================================================
(define *openblas-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "libopenblas.so.0")
        (set! *openblas-available* #t)))))

(define cblas-sdot  #f)
(define cblas-ddot  #f)
(define cblas-saxpy #f)
(define cblas-daxpy #f)
(define cblas-scopy #f)
(define cblas-dcopy #f)
(define cblas-sscal #f)
(define cblas-dscal #f)
(define cblas-sgemv #f)
(define cblas-dgemv #f)
(define cblas-sgemm #f)
(define cblas-dgemm #f)

(when *openblas-available*
  (set! cblas-sdot  (foreign-procedure "cblas_sdot" (int void* int void* int) float))
  (set! cblas-ddot  (foreign-procedure "cblas_ddot" (int void* int void* int) double))
  (set! cblas-saxpy (foreign-procedure "cblas_saxpy" (int float void* int void* int) void))
  (set! cblas-daxpy (foreign-procedure "cblas_daxpy" (int double void* int void* int) void))
  (set! cblas-scopy (foreign-procedure "cblas_scopy" (int void* int void* int) void))
  (set! cblas-dcopy (foreign-procedure "cblas_dcopy" (int void* int void* int) void))
  (set! cblas-sscal (foreign-procedure "cblas_sscal" (int float void* int) void))
  (set! cblas-dscal (foreign-procedure "cblas_dscal" (int double void* int) void))
  (set! cblas-sgemv (foreign-procedure "cblas_sgemv" (int int int float void* int void* int float void* int) void))
  (set! cblas-dgemv (foreign-procedure "cblas_dgemv" (int int int double void* int void* int double void* int) void))
  (set! cblas-sgemm (foreign-procedure "cblas_sgemm" (int int int int int int float void* int void* int float void* int) void))
  (set! cblas-dgemm (foreign-procedure "cblas_dgemm" (int int int int int int double void* int void* int double void* int) void)))

;; ============================================================
;; Part 2: LAPACK — 可选加载
;; ============================================================
(define *lapack-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "liblapacke.so.3")
        (set! *lapack-available* #t)))))

(define lapack-dgesv  #f)
(define lapack-sgesv  #f)
(define lapack-dgesdd #f)
(define lapack-sgesdd #f)
(define lapack-dsyevd #f)
(define lapack-dgeqrf #f)

(when *lapack-available*
  (set! lapack-dgesv  (foreign-procedure "LAPACKE_dgesv" (int int int void* int void* void* int) int))
  (set! lapack-sgesv  (foreign-procedure "LAPACKE_sgesv" (int int int void* int void* void* int) int))
  (set! lapack-dgesdd (foreign-procedure "LAPACKE_dgesdd" (int int int int void* int void* void* int void* int) int))
  (set! lapack-sgesdd (foreign-procedure "LAPACKE_sgesdd" (int int int int void* int void* void* int void* int) int))
  (set! lapack-dsyevd (foreign-procedure "LAPACKE_dsyevd" (int int int int void* int void*) int))
  (set! lapack-dgeqrf (foreign-procedure "LAPACKE_dgeqrf" (int int int void* int void*) int)))

;; ============================================================
;; Part 3: CUDA cuBLAS — GPU 矩阵运算
;; ============================================================
;; CUDA libs are loaded by torch internally — do NOT preload with RTLD_LOCAL
(define *cuda-available* #f)

(define cublas-handle #f)
(define cublas-create #f)
(define cublas-destroy #f)
(define cublas-sgemm #f)
(define cublas-dgemm #f)
(define cublas-saxpy #f)
(define cublas-daxpy #f)
(define cublas-sdot #f)
(define cublas-ddot #f)
(define cublas-dcopy #f)

(when *cuda-available*
  (set! cublas-create (foreign-procedure "cublasCreate_v2" (void*) int))
  (set! cublas-destroy (foreign-procedure "cublasDestroy_v2" (void*) int))
  (set! cublas-sgemm (foreign-procedure "cublasSgemm_v2"
    (void* int int int int int int float void* int void* int float void* int) int))
  (set! cublas-dgemm (foreign-procedure "cublasDgemm_v2"
    (void* int int int int int int void* void* int void* int void* void* int) int))
  (set! cublas-saxpy (foreign-procedure "cublasSaxpy_v2"
    (void* int float void* int void* int) int))
  (set! cublas-daxpy (foreign-procedure "cublasDaxpy_v2"
    (void* int double void* int void* int) int))
  (set! cublas-ddot (foreign-procedure "cublasDdot_v2"
    (void* int void* int void* int) double))
  (set! cublas-dcopy (foreign-procedure "cublasDcopy_v2"
    (void* int void* int void* int) int))
  ;; 初始化 cuBLAS handle
  (let ((h (foreign-alloc 8)))
    (cublas-create h)
    (set! cublas-handle (foreign-ref 'void* h 0))
    (foreign-free h)))

;; ============================================================
;; Part 3a: cuRAND — GPU 随机数生成（权重初始化/dropout）
;; ============================================================
;; loaded by torch internally
(define *curand-available* #f)

(define curand-create #f)
(define curand-destroy #f)
(define curand-set-seed #f)
(define curand-uniform #f)
(define curand-normal #f)

(when *curand-available*
  (set! curand-create (foreign-procedure "curandCreateGenerator" (void* int) int))
  (set! curand-destroy (foreign-procedure "curandDestroyGenerator" (void*) int))
  (set! curand-set-seed (foreign-procedure "curandSetPseudoRandomGeneratorSeed" (void* int) int))
  (set! curand-uniform (foreign-procedure "curandGenerateUniform" (void* void* int) int))
  (set! curand-normal (foreign-procedure "curandGenerateNormal" (void* void* int double double) int)))

;; ============================================================
;; Part 4: cuSOLVER — GPU 矩阵分解（SVD/Cholesky）
;; ============================================================
;; loaded by torch internally
(define *cusolver-available* #f)

(define cusolver-dn-create #f)
(define cusolver-dn-destroy #f)
(define cusolver-dgesvd #f)
(define cusolver-dpotrf #f)

(when *cusolver-available*
  (set! cusolver-dn-create (foreign-procedure "cusolverDnCreate" (void*) int))
  (set! cusolver-dn-destroy (foreign-procedure "cusolverDnDestroy" (void*) int))
  (set! cusolver-dgesvd (foreign-procedure "cusolverDnDgesvd"
    (void* int int int int void* int void* void* int void* int void* int void* void*) int))
  (set! cusolver-dpotrf (foreign-procedure "cusolverDnDpotrf"
    (void* int int void* int void* int void*) int)))

;; ============================================================
;; Part 5: cuDNN — GPU 深度学习原语
;; ============================================================
;; loaded by torch internally
(define *cudnn-available* #f)

(define cudnn-create #f)
(define cudnn-destroy #f)
(define cudnn-create-tensor-desc #f)
(define cudnn-set-tensor-4d #f)
(define cudnn-create-filter-desc #f)
(define cudnn-set-filter-4d #f)
(define cudnn-create-conv-desc #f)
(define cudnn-set-conv-2d #f)
(define cudnn-conv-forward #f)
(define cudnn-activation-forward #f)
(define cudnn-activation-backward #f)
(define cudnn-pooling-forward #f)
(define cudnn-softmax-forward #f)
(define cudnn-batchnorm-forward #f)

(when *cudnn-available*
  (call-with-current-continuation
    (lambda (return)
      (with-exception-handler
        (lambda (e) #f (return))
        (lambda ()
          (set! cudnn-create (foreign-procedure "cudnnCreate" (void*) int))
          (set! cudnn-destroy (foreign-procedure "cudnnDestroy" (void*) int))
          (set! cudnn-create-tensor-desc (foreign-procedure "cudnnCreateTensorDescriptor" (void*) int))
          (set! cudnn-set-tensor-4d (foreign-procedure "cudnnSetTensor4dDescriptor" (void* int int int int int int) int))
          (set! cudnn-create-filter-desc (foreign-procedure "cudnnCreateFilterDescriptor" (void*) int))
          (set! cudnn-set-filter-4d (foreign-procedure "cudnnSetFilter4dDescriptor" (void* int int int int int int) int))
          (set! cudnn-create-conv-desc (foreign-procedure "cudnnCreateConvolutionDescriptor" (void*) int))
          (set! cudnn-set-conv-2d (foreign-procedure "cudnnSetConvolution2dDescriptor" (void* int int int int int int int int) int))
          (set! cudnn-conv-forward (foreign-procedure "cudnnConvolutionForward"
            (void* void* void* void* void* void* void* int void* int void* void* void*) int))
          (set! cudnn-activation-forward (foreign-procedure "cudnnActivationForward"
            (void* int void* void* void* void* void* void*) int))
          (set! cudnn-activation-backward (foreign-procedure "cudnnActivationBackward"
            (void* int void* void* void* void* void* void* void* void* void* void*) int))
          (set! cudnn-pooling-forward (foreign-procedure "cudnnPoolingForward"
            (void* void* void* void* void* void* void* void*) int))
          (set! cudnn-softmax-forward (foreign-procedure "cudnnSoftmaxForward"
            (void* int int void* void* void* void* void* void*) int))
          (set! cudnn-batchnorm-forward (foreign-procedure "cudnnBatchNormalizationForwardTraining"
            (void* int void* void* void* void* void* void* void* void* void* void* void* double) int)))))))

;; ============================================================
;; Part 6: libcurl — HTTP 数据获取
;; ============================================================
(define *curl-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "libcurl.so.4")
        (set! *curl-available* #t)))))

(define curl-easy-init #f)
(define curl-easy-setopt #f)
(define curl-easy-perform #f)
(define curl-easy-cleanup #f)
(define curl-slist-append #f)

(when *curl-available*
  (set! curl-easy-init (foreign-procedure "curl_easy_init" () void*))
  (set! curl-easy-setopt (foreign-procedure "curl_easy_setopt" (void* int void*) int))
  (set! curl-easy-perform (foreign-procedure "curl_easy_perform" (void*) int))
  (set! curl-easy-cleanup (foreign-procedure "curl_easy_cleanup" (void*) void))
  (set! curl-slist-append (foreign-procedure "curl_slist_append" (void* string) void*)))

;; ============================================================
;; Part 7: libcjson — JSON 解析
;; ============================================================
(define *cjson-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "libcjson.so.1")
        (set! *cjson-available* #t)))))

(define cjson-parse #f)
(define cjson-print #f)
(define cjson-delete #f)
(define cjson-get-object-item #f)
(define cjson-get-array-item #f)
(define cjson-get-array-size #f)
(define cjson-is-number #f)
(define cjson-is-string #f)
(define cjson-get-number #f)
(define cjson-get-string #f)

(when *cjson-available*
  (set! cjson-parse (foreign-procedure "cJSON_Parse" (string) void*))
  (set! cjson-print (foreign-procedure "cJSON_Print" (void*) string))
  (set! cjson-delete (foreign-procedure "cJSON_Delete" (void*) void))
  (set! cjson-get-object-item (foreign-procedure "cJSON_GetObjectItem" (void* string) void*))
  (set! cjson-get-array-item (foreign-procedure "cJSON_GetArrayItem" (void* int) void*))
  (set! cjson-get-array-size (foreign-procedure "cJSON_GetArraySize" (void*) int))
  (set! cjson-is-number (foreign-procedure "cJSON_IsNumber" (void*) int))
  (set! cjson-is-string (foreign-procedure "cJSON_IsString" (void*) int))
  (set! cjson-get-number (foreign-procedure "cJSON_GetNumberValue" (void*) double))
  (set! cjson-get-string (foreign-procedure "cJSON_GetStringValue" (void*) string)))

;; ============================================================
;; Part 8: XGBoost — 树模型训练/推理
;; ============================================================
(define *xgboost-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "libxgboost.so")
        (set! *xgboost-available* #t)))))

(define xgb-create #f)
(define xgb-set-param #f)
(define xgb-train #f)
(define xgb-predict #f)
(define xgb-dmatrix-create #f)
(define xgb-dmatrix-set-float #f)

(when *xgboost-available*
  (set! xgb-create (foreign-procedure "XGBoosterCreate" (void* int) int))
  (set! xgb-set-param (foreign-procedure "XGBoosterSetParam" (void* string string) int))
  (set! xgb-train (foreign-procedure "XGBoosterTrainOneIter" (void* void*) int))
  (set! xgb-predict (foreign-procedure "XGBoosterPredict"
    (void* void* int int void* void*) int))
  (set! xgb-dmatrix-create (foreign-procedure "XGDMatrixCreateFromMat"
    (void* int int double void*) int))
  (set! xgb-dmatrix-set-float (foreign-procedure "XGDMatrixSetFloatInfo"
    (void* string void* int) int)))

;; ============================================================
;; Part 9: LightGBM — 树模型（替代方案）
;; ============================================================
(define *lightgbm-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "liblightgbm.so")
        (set! *lightgbm-available* #t)))))

(define lgbm-create #f)
(define lgbm-predict #f)
(define lgbm-save #f)
(define lgbm-load #f)

(when *lightgbm-available*
  (set! lgbm-create (foreign-procedure "LGBM_BoosterCreateFromMat"
    (void* int int string void*) int))
  (set! lgbm-predict (foreign-procedure "LGBM_BoosterPredictForMat"
    (void* void* int int int int string void* void*) int))
  (set! lgbm-save (foreign-procedure "LGBM_BoosterSaveModel"
    (void* int string) int))
  (set! lgbm-load (foreign-procedure "LGBM_BoosterLoadModel"
    (string void*) int)))

;; ============================================================
;; Part 10: ONNX Runtime — 模型推理部署
;; ============================================================
(define *onnx-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e) #f (return))
      (lambda ()
        (load-shared-object "libonnxruntime.so")
        (set! *onnx-available* #t)))))

(define onnx-create-session #f)
(define onnx-run #f)

(when *onnx-available*
  (call-with-current-continuation
    (lambda (return)
      (with-exception-handler
        (lambda (e) #f (return))
        (lambda ()
          (set! onnx-create-session (foreign-procedure "OrtCreateSession"
            (void* string void* void*) int))
          (set! onnx-run (foreign-procedure "OrtRun"
            (void* void* void* void* int void* void* int) int)))))))
;; ============================================================
;; Part 4: Python 风格包装 — numpy 兼容层（需要 OpenBLAS）
;; ============================================================

(define (np-dot a b n)
  "向量点积 a·b"
  (if *openblas-available* (cblas-ddot n a 1 b 1) (begin (display "OpenBLAS not available\n") 0.0)))

(define (np-daxpy n alpha x y)
  "向量线性组合 y = alpha*x + y"
  (if *openblas-available* (cblas-daxpy n alpha x 1 y 1) -1))

(define (np-copy n x y)
  "向量拷贝 y = x"
  (if *openblas-available* (cblas-dcopy n x 1 y 1) -1))

(define (np-scal n alpha x)
  "向量缩放 x = alpha*x"
  (if *openblas-available* (cblas-dscal n alpha x 1) -1))

(define (np-gemv trans m n alpha a x beta y)
  "矩阵×向量 y = alpha*A*x + beta*y"
  (if *openblas-available* (cblas-dgemv 101 trans m n alpha a n x 1 beta y 1) -1))

(define (np-gemm trans-a trans-b m n k alpha a b beta c)
  "矩阵乘法 C = alpha*A*B + beta*C"
  (if *openblas-available* (cblas-dgemm 101 trans-a trans-b m n k alpha a k b n beta c n) -1))

;; ====== tagged array 抽象：#(data len) ======
;; 所有 numpy 风格函数统一操作 tagged array，自动携带长度

(define (make-tagged-array data n)
  (vector data n))

(define (tagged-array-data a)
  (vector-ref a 0))

(define (tagged-array-len a)
  (vector-ref a 1))

(define (tagged-array? x)
  (and (vector? x) (= (vector-length x) 2) (integer? (vector-ref x 1))))


;; ====== numpy 数学函数（操作 tagged array） ======

(define (np-array v . maybe-n)
  "从 Scheme vector/list 创建 float64 tagged array，或透传已有 tagged array"
  (if (tagged-array? v)
    v
    (let* ((n (if (null? maybe-n)
                  (if (vector? v) (vector-length v) (length v))
                  (car maybe-n)))
           (ptr (make-float-array n)))
      (do ((i 0 (+ i 1))) ((= i n) (make-tagged-array ptr n))
        (float-array-set ptr i (if (vector? v) (vector-ref v i) (list-ref v i)))))))

(define (np-from-list lst)
  "从 Scheme list 创建 float64 tagged array"
  (np-array lst))

(define (np-dot a b)
  "向量点积 a·b"
  (let ((n (tagged-array-len a))
        (da (tagged-array-data a))
        (db (tagged-array-data b)))
    (if *openblas-available*
      (cblas-ddot n da 1 db 1)
      (begin (display "OpenBLAS not available\n") 0.0))))

(define (np-daxpy alpha x y)
  "向量线性组合 y = alpha*x + y"
  (let ((n (tagged-array-len x))
        (dx (tagged-array-data x))
        (dy (tagged-array-data y)))
    (if *openblas-available* (cblas-daxpy n alpha dx 1 dy 1) -1)))

(define (np-copy x)
  "向量拷贝 y = x"
  (let ((n (tagged-array-len x))
        (dx (tagged-array-data x))
        (dy (tagged-array-data (np-zeros n))))
    (if *openblas-available* (cblas-dcopy n dx 1 dy 1) -1)
    (make-tagged-array dy n)))

(define (np-scal alpha x)
  "向量缩放 x = alpha*x"
  (let ((n (tagged-array-len x))
        (dx (tagged-array-data x)))
    (if *openblas-available* (cblas-dscal n alpha dx 1) -1)
    x))

(define (np-gemm trans-a trans-b m n k alpha a b beta c)
  "矩阵乘法 C = alpha*A*B + beta*C"
  (let ((da (tagged-array-data a))
        (db (tagged-array-data b))
        (dc (tagged-array-data c)))
    (if *openblas-available*
      (cblas-dgemm 101 trans-a trans-b m n k alpha da k db n beta dc n)
      -1)))

(define (np-sum a)
  "求和"
  (let ((n (tagged-array-len a))
        (ptr (tagged-array-data a)))
    (do ((i 0 (+ i 1)) (s 0.0 (+ s (foreign-ref 'double ptr (* i 8))))) ((= i n) s))))

(define (np-mean a)
  "平均值"
  (/ (np-sum a) (tagged-array-len a)))

(define (np-max a)
  "最大值"
  (let ((n (tagged-array-len a))
        (ptr (tagged-array-data a)))
    (do ((i 1 (+ i 1)) (m (foreign-ref 'double ptr 0) (max m (foreign-ref 'double ptr (* i 8))))) ((= i n) m))))

(define (np-min a)
  "最小值"
  (let ((n (tagged-array-len a))
        (ptr (tagged-array-data a)))
    (do ((i 1 (+ i 1)) (m (foreign-ref 'double ptr 0) (min m (foreign-ref 'double ptr (* i 8))))) ((= i n) m))))

(define (np-zeros n)
  "创建全零 tagged array"
  (make-tagged-array (make-float-array n) n))

(define (np-ones n)
  "创建全一 tagged array"
  (let ((ptr (make-float-array n)))
    (do ((i 0 (+ i 1))) ((= i n) (make-tagged-array ptr n))
      (foreign-set! 'double ptr (* i 8) 1.0))))

(define (np-sqrt a)
  "逐元素平方根"
  (let* ((n (tagged-array-len a))
         (ptr (tagged-array-data a))
         (r (make-float-array n)))
    (do ((i 0 (+ i 1))) ((= i n) (make-tagged-array r n))
      (foreign-set! 'double r (* i 8) (sqrt (foreign-ref 'double ptr (* i 8)))))))

(define (np-exp a)
  "逐元素指数"
  (let* ((n (tagged-array-len a))
         (ptr (tagged-array-data a))
         (r (make-float-array n)))
    (do ((i 0 (+ i 1))) ((= i n) (make-tagged-array r n))
      (foreign-set! 'double r (* i 8) (exp (foreign-ref 'double ptr (* i 8)))))))

(define (np-abs a)
  "逐元素绝对值"
  (let* ((n (tagged-array-len a))
         (ptr (tagged-array-data a))
         (r (make-float-array n)))
    (do ((i 0 (+ i 1))) ((= i n) (make-tagged-array r n))
      (foreign-set! 'double r (* i 8) (abs (foreign-ref 'double ptr (* i 8)))))))

(define (np-arange start end step)
  "arange: 从 start 到 end，步长 step"
  (let* ((n (max 0 (inexact->exact (ceiling (/ (- end start) step)))))
         (ptr (make-float-array n)))
    (do ((i 0 (+ i 1)) (v start (+ v step))) ((= i n) (make-tagged-array ptr n))
      (foreign-set! 'double ptr (* i 8) v))))

(define (np-linspace start end n)
  "linspace: 从 start 到 end，均匀 n 个点"
  (let ((ptr (make-float-array n))
        (step (/ (- end start) (max 1 (- n 1)))))
    (do ((i 0 (+ i 1)) (v start (+ v step))) ((= i n) (make-tagged-array ptr n))
      (foreign-set! 'double ptr (* i 8) v))))

(define (np-concatenate arrays)
  "拼接多个 tagged array"
  (let* ((sizes (map tagged-array-len arrays))
         (total-size (apply + sizes))
         (result (make-float-array total-size))
         (offsets (let loop ((acc 0) (szs sizes))
                    (if (null? szs) '()
                      (cons acc (loop (+ acc (car szs)) (cdr szs)))))))
    (let loop ((arrs arrays) (offs offsets))
      (if (null? arrs)
        (make-tagged-array result total-size)
        (let ((src (tagged-array-data (car arrs)))
              (offset (car offs))
              (len (tagged-array-len (car arrs))))
          (do ((i 0 (+ i 1))) ((= i len))
            (foreign-set! 'double result (* (+ offset i) 8)
              (foreign-ref 'double src (* i 8))))
          (loop (cdr arrs) (cdr offs)))))))

(define (np-clip a lo hi)
  "截断值到 [lo, hi] 范围"
  (let* ((n (tagged-array-len a))
         (ptr (tagged-array-data a))
         (r (make-float-array n)))
    (do ((i 0 (+ i 1))) ((= i n) (make-tagged-array r n))
      (foreign-set! 'double r (* i 8)
        (max lo (min hi (foreign-ref 'double ptr (* i 8))))))))

(define (np-argmax a)
  "最大值的索引"
  (let ((n (tagged-array-len a))
        (ptr (tagged-array-data a)))
    (do ((i 1 (+ i 1)) (mi 0) (mv (foreign-ref 'double ptr 0)))
        ((= i n) mi)
      (let ((v (foreign-ref 'double ptr (* i 8))))
        (when (> v mv) (set! mi i) (set! mv v))))))

;; 兼容旧 API：允许 (np-dot a b n) 直接传裸指针（弃用）
(define (np-dot-compat a b . maybe-n)
  (if (null? maybe-n)
    (np-dot a b)
    (np-dot (make-tagged-array a (car maybe-n)) (make-tagged-array b (car maybe-n)))))

;; 如果 import 映射生成的是 np-dot，上面定义的是 np-dot
;; 旧代码可能生成 (np-dot a b n)，下面加一个接受 3 参数的包装会覆盖
;; 但 Scheme 不支持重载，因此保留旧名 np-dot-old，让新代码用 np-dot
(define np-dot-old np-dot-compat)

;; ============================================================
;; Part 5: Python 风格包装 — scipy.linalg 兼容层
;; ============================================================

(define (la-solve n a b)
  "解线性方程组 Ax = b"
  (lapack-dgesv 101 n 1 a n b 1))

(define (la-svd m n a s u vt)
  "SVD 分解 A = U*S*V^T"
  (lapack-dgesdd 101 65 m n a n s u m vt n))

(define (la-eigvals n a w)
  "特征值分解 (对称矩阵)"
  (lapack-dsyevd 101 78 78 n a n w))

;; ============================================================
;; Part 11: libTorch Standard API — 通过 libtorch_std_helper.so
;; ============================================================
(define *torch-available* #f)
(call-with-current-continuation
  (lambda (return)
    (with-exception-handler
      (lambda (e)
        (set! *torch-available* #f)
        (return))
      (lambda ()
        (load-shared-object "libtorch_std_helper.so")
        (set! *torch-available* #t)))))

;; dtype 常量
(define *torch-dtype-float32* 0)
(define *torch-dtype-float64* 1)
(define *torch-dtype-int32* 2)
(define *torch-dtype-int64* 3)

;; 核心 foreign-procedure 声明
(define torch-std-tensor-from-blob #f)
(define torch-std-zeros #f)
(define torch-std-ones #f)
(define torch-std-empty #f)
(define torch-std-full #f)
(define torch-std-randn #f)
(define torch-std-randint #f)
(define torch-std-clone #f)
(define torch-std-detach #f)
(define torch-std-to-dtype #f)
(define torch-std-dtype #f)
(define torch-std-scalar-tensor #f)
(define torch-std-scalar-tensor-like #f)
(define torch-std-index-rows2 #f)
(define torch-std-arange-f-cuda #f)
(define torch-std-arange-f-offset #f)
(define torch-std-cat-int64 #f)
(define torch-std-last-argmax #f)
(define torch-std-image-resize-float #f)
(define torch-std-rsqrt #f)
(define torch-std-topk #f)
(define torch-std-tpack-load #f)
(define torch-std-tpack-get #f)
(define torch-std-cos #f)
(define torch-std-sin #f)
(define torch-std-outer #f)
(define torch-std-rope-inv #f)
(define torch-std-arange-f #f)
(define torch-std-causal-mask #f)
(define torch-std-delete-tensor #f)
(define torch-std-numel #f)
(define torch-std-ndim #f)
(define torch-std-shape #f)
(define torch-std-to-double-array #f)
(define torch-std-to-float-array #f)
(define torch-std-to-int64-array #f)

(define torch-std-add #f)
(define torch-std-sub #f)
(define torch-std-mul #f)
(define torch-std-div #f)
(define torch-std-pow #f)
(define torch-std-exp #f)
(define torch-std-log #f)
(define torch-std-sqrt #f)
(define torch-std-neg #f)
(define torch-std-abs #f)

(define torch-std-relu #f)
(define torch-std-leaky-relu #f)
(define torch-std-sigmoid #f)
(define torch-std-tanh #f)
(define torch-std-softmax #f)
(define torch-std-log-softmax #f)

(define torch-std-sum #f)
(define torch-std-sum-dim #f)
(define torch-std-mean #f)
(define torch-std-mean-dim #f)
(define torch-std-max #f)
(define torch-std-max-dim #f)
(define torch-std-min #f)
(define torch-std-min-dim #f)

(define torch-std-argmax #f)
(define torch-std-argmax-dim1 #f)
(define torch-std-multinomial #f)
(define torch-std-gather #f)
(define torch-std-index-select #f)
(define torch-std-index-rows2 #f)
(define torch-std-index-tensor #f)

(define torch-std-reshape #f)
(define torch-std-transpose #f)
(define torch-std-permute #f)
(define torch-std-squeeze #f)
(define torch-std-unsqueeze #f)
(define torch-std-cat #f)
(define torch-std-stack #f)

(define torch-std-matmul #f)
(define torch-std-linear #f)
(define torch-std-conv1d #f)
(define torch-std-conv2d #f)
(define torch-std-max-pool2d #f)
(define torch-std-avg-pool2d #f)
(define torch-std-batch-norm1d #f)
(define torch-std-batch-norm2d #f)

(define torch-std-mse-loss #f)
(define torch-std-l1-loss #f)
(define torch-std-cross-entropy-loss #f)
(define torch-std-nll-loss #f)
(define torch-std-bce-loss #f)
(define torch-std-bce-with-logits-loss #f)

(define torch-std-requires-grad #f)
(define torch-std-set-requires-grad #f)
(define torch-std-backward #f)
(define torch-std-backward-retain-graph #f)
(define torch-std-grad #f)
(define torch-std-zero-grad #f)
(define torch-std-has-grad #f)

(define torch-std-sgd-create #f)
(define torch-std-adam-create #f)
(define torch-std-adamw-create #f)
(define torch-std-optimizer-step #f)
(define torch-std-optimizer-zero-grad #f)
(define torch-std-optimizer-destroy #f)

(define torch-std-narrow #f)
(define torch-std-slice #f)
(define torch-std-masked-select #f)
(define torch-std-where #f)
(define torch-std-eq #f)
(define torch-std-gt #f)
(define torch-std-lt #f)
(define torch-std-ge #f)
(define torch-std-le #f)
(define torch-std-clamp #f)
(define torch-std-clip-grad-norm #f)

(define torch-std-manual-seed #f)
(define torch-std-cuda-is-available #f)
(define torch-std-to-cuda #f)
(define torch-std-to-cpu #f)
(define torch-std-is-cuda #f)

;; -- JIT & SD extensions --
(define torch-std-jit-load #f)
(define torch-std-jit-forward #f)
(define torch-std-jit-parameters #f)
(define torch-std-jit-module-delete #f)
(define torch-std-sd-unet-forward #f)
(define torch-std-load-image #f)
(define torch-std-save-image #f)
(define torch-std-ddpm-betas #f)
(define torch-std-ddpm-add-noise #f)
(define torch-std-jit-named-parameters #f)
(define torch-std-save-state-dict #f)

;; safetensors
(define torch-std-safetensors-load #f)
(define torch-std-safetensors-count #f)
(define torch-std-safetensors-name #f)
(define torch-std-safetensors-tensor #f)
(define torch-std-safetensors-free #f)
(define torch-std-safetensors-get-tensor-by-name #f)
;; LoRA
(define torch-std-lora-apply #f)
(define torch-std-lora-merge-into #f)
;; Samplers
(define torch-std-sample-ddim #f)
(define torch-std-sample-euler #f)
(define torch-std-sample-euler-ancestral #f)
(define torch-std-sample-dpmpp-2m #f)
(define torch-std-sampler-sigmas #f)
;; Image processing
(define torch-std-image-resize #f)
(define torch-std-image-crop #f)
(define torch-std-image-composite #f)
(define torch-std-color-convert #f)
;; ControlNet
(define torch-std-controlnet-forward #f)
(define torch-std-controlnet-apply #f)
;; VAE tiling
(define torch-std-vae-encode-tiled #f)
(define torch-std-vae-decode-tiled #f)
;; CLIP tokenizer
(define torch-std-clip-tokenizer-create #f)
(define torch-std-clip-tokenizer-encode #f)
(define torch-std-clip-tokenizer-free #f)
;; CLIP text encoder forward
(define torch-std-clip-text-forward #f)

(when *torch-available*
  (set! torch-std-tensor-from-blob
    (foreign-procedure "torch_std_tensor_from_blob" (void* void* int int) void*))
  (set! torch-std-zeros
    (foreign-procedure "torch_std_zeros" (void* int int) void*))
  (set! torch-std-ones
    (foreign-procedure "torch_std_ones" (void* int int) void*))
  (set! torch-std-empty
    (foreign-procedure "torch_std_empty" (void* int int) void*))
  (set! torch-std-full
    (foreign-procedure "torch_std_full" (void* int double int) void*))
  (set! torch-std-randn
    (foreign-procedure "torch_std_randn" (void* int int) void*))
  (set! torch-std-randint
    (foreign-procedure "torch_std_randint" (long long void* int int) void*))
  (set! torch-std-clone
    (foreign-procedure "torch_std_clone" (void*) void*))
  (set! torch-std-detach
    (foreign-procedure "torch_std_detach" (void*) void*))
  (set! torch-std-to-dtype
    (foreign-procedure "torch_std_to_dtype" (void* int) void*))
  (set! torch-std-dtype
    (foreign-procedure "torch_std_dtype" (void*) int))
  (set! torch-std-scalar-tensor
    (foreign-procedure "torch_std_scalar_tensor" (double) void*))
  (set! torch-std-scalar-tensor-like
    (foreign-procedure "torch_std_scalar_tensor_like" (void* double) void*))
  (set! torch-std-index-rows2
    (foreign-procedure "torch_std_index_rows2" (void* void*) void*))
  (set! torch-std-arange-f-cuda
    (foreign-procedure "torch_std_arange_f_cuda" (long) void*))
  (set! torch-std-arange-f-offset
    (foreign-procedure "torch_std_arange_f_offset" (long long) void*))
  (set! torch-std-cat-int64
    (foreign-procedure "torch_std_cat_int64" (void* long) void*))
  (set! torch-std-last-argmax
    (foreign-procedure "torch_std_last_argmax" (void*) long))
  (set! torch-std-image-resize-float
    (foreign-procedure "torch_std_image_resize_float" (void* int int string) void*))
  (set! torch-std-rsqrt
    (foreign-procedure "torch_std_rsqrt" (void*) void*))
  (set! torch-std-topk
    (foreign-procedure "torch_std_topk" (void* long long int) void*))
  (set! torch-std-tpack-load
    (foreign-procedure "torch_std_tpack_load" (string) void*))
  (set! torch-std-tpack-get
    (foreign-procedure "torch_std_tpack_tensor" (string) void*))
  (set! torch-std-cos
    (foreign-procedure "torch_std_cos" (void*) void*))
  (set! torch-std-sin
    (foreign-procedure "torch_std_sin" (void*) void*))
  (set! torch-std-outer
    (foreign-procedure "torch_std_outer" (void* void*) void*))
  (set! torch-std-rope-inv
    (foreign-procedure "torch_std_rope_inv" (long double) void*))
  (set! torch-std-arange-f
    (foreign-procedure "torch_std_arange_f" (long) void*))
  (set! torch-std-causal-mask
    (foreign-procedure "torch_std_causal_mask" (long) void*))
  (set! torch-std-delete-tensor
    (foreign-procedure "torch_std_delete_tensor" (void*) void))
  (set! torch-std-numel
    (foreign-procedure "torch_std_numel" (void*) long))
  (set! torch-std-ndim
    (foreign-procedure "torch_std_ndim" (void*) int))
  (set! torch-std-shape
    (foreign-procedure "torch_std_shape" (void* void*) void))
  (set! torch-std-to-double-array
    (foreign-procedure "torch_std_to_double_array" (void* void* long) void))
  (set! torch-std-to-float-array
    (foreign-procedure "torch_std_to_float_array" (void* void* long) void))
  (set! torch-std-to-int64-array
    (foreign-procedure "torch_std_to_int64_array" (void* void* long) void))

  (set! torch-std-add
    (foreign-procedure "torch_std_add" (void* void*) void*))
  (set! torch-std-sub
    (foreign-procedure "torch_std_sub" (void* void*) void*))
  (set! torch-std-mul
    (foreign-procedure "torch_std_mul" (void* void*) void*))
  (set! torch-std-div
    (foreign-procedure "torch_std_div" (void* void*) void*))
  (set! torch-std-pow
    (foreign-procedure "torch_std_pow" (void* double) void*))
  (set! torch-std-exp
    (foreign-procedure "torch_std_exp" (void*) void*))
  (set! torch-std-log
    (foreign-procedure "torch_std_log" (void*) void*))
  (set! torch-std-sqrt
    (foreign-procedure "torch_std_sqrt" (void*) void*))
  (set! torch-std-neg
    (foreign-procedure "torch_std_neg" (void*) void*))
  (set! torch-std-abs
    (foreign-procedure "torch_std_abs" (void*) void*))

  (set! torch-std-relu
    (foreign-procedure "torch_std_relu" (void*) void*))
  (set! torch-std-leaky-relu
    (foreign-procedure "torch_std_leaky_relu" (void* double) void*))
  (set! torch-std-sigmoid
    (foreign-procedure "torch_std_sigmoid" (void*) void*))
  (set! torch-std-tanh
    (foreign-procedure "torch_std_tanh" (void*) void*))
  (set! torch-std-softmax
    (foreign-procedure "torch_std_softmax" (void* long) void*))
  (set! torch-std-log-softmax
    (foreign-procedure "torch_std_log_softmax" (void* long) void*))

  (set! torch-std-sum
    (foreign-procedure "torch_std_sum" (void*) void*))
  (set! torch-std-sum-dim
    (foreign-procedure "torch_std_sum_dim" (void* long int) void*))
  (set! torch-std-mean
    (foreign-procedure "torch_std_mean" (void*) void*))
  (set! torch-std-mean-dim
    (foreign-procedure "torch_std_mean_dim" (void* long int) void*))
  (set! torch-std-max
    (foreign-procedure "torch_std_max" (void*) void*))
  (set! torch-std-max-dim
    (foreign-procedure "torch_std_max_dim" (void* long int) void*))
  (set! torch-std-min
    (foreign-procedure "torch_std_min" (void*) void*))
  (set! torch-std-min-dim
    (foreign-procedure "torch_std_min_dim" (void* long int) void*))

  (set! torch-std-argmax
    (foreign-procedure "torch_std_argmax" (void*) long))
  (set! torch-std-argmax-dim1
    (foreign-procedure "torch_std_argmax_dim1" (void* long) long))
  (set! torch-std-multinomial
    (foreign-procedure "torch_std_multinomial" (void* long int) void*))
  (set! torch-std-gather
    (foreign-procedure "torch_std_gather" (void* long void*) void*))
  (set! torch-std-index-select
    (foreign-procedure "torch_std_index_select" (void* long void*) void*))
  (set! torch-std-index-rows
    (foreign-procedure "torch_std_index_rows" (void* void*) void*))
  (set! torch-std-index-tensor
    (foreign-procedure "torch_std_index_tensor" (void* void*) void*))

  (set! torch-std-reshape
    (foreign-procedure "torch_std_reshape" (void* void* int) void*))
  (set! torch-std-transpose
    (foreign-procedure "torch_std_transpose" (void* long long) void*))
  (set! torch-std-permute
    (foreign-procedure "torch_std_permute" (void* void* int) void*))
  (set! torch-std-squeeze
    (foreign-procedure "torch_std_squeeze" (void* long) void*))
  (set! torch-std-unsqueeze
    (foreign-procedure "torch_std_unsqueeze" (void* long) void*))
  (set! torch-std-cat
    (foreign-procedure "torch_std_cat" (void* int long) void*))
  (set! torch-std-stack
    (foreign-procedure "torch_std_stack" (void* int long) void*))

  (set! torch-std-matmul
    (foreign-procedure "torch_std_matmul" (void* void*) void*))
  (set! torch-std-linear
    (foreign-procedure "torch_std_linear" (void* void* void*) void*))
  (set! torch-std-conv1d
    (foreign-procedure "torch_std_conv1d" (void* void* void* long long long long) void*))
  (set! torch-std-conv2d
    (foreign-procedure "torch_std_conv2d" (void* void* void* long long long long long long long) void*))
  (set! torch-std-max-pool2d
    (foreign-procedure "torch_std_max_pool2d" (void* long long long long long long long long) void*))
  (set! torch-std-avg-pool2d
    (foreign-procedure "torch_std_avg_pool2d" (void* long long long long long long) void*))
  (set! torch-std-batch-norm1d
    (foreign-procedure "torch_std_batch_norm1d" (void* void* void* void* void* int double double) void*))
  (set! torch-std-batch-norm2d
    (foreign-procedure "torch_std_batch_norm2d" (void* void* void* void* void* int double double) void*))

  (set! torch-std-mse-loss
    (foreign-procedure "torch_std_mse_loss" (void* void* string) void*))
  (set! torch-std-l1-loss
    (foreign-procedure "torch_std_l1_loss" (void* void* string) void*))
  (set! torch-std-cross-entropy-loss
    (foreign-procedure "torch_std_cross_entropy_loss" (void* void* string) void*))
  (set! torch-std-nll-loss
    (foreign-procedure "torch_std_nll_loss" (void* void* string) void*))
  (set! torch-std-bce-loss
    (foreign-procedure "torch_std_bce_loss" (void* void* string) void*))
  (set! torch-std-bce-with-logits-loss
    (foreign-procedure "torch_std_bce_with_logits_loss" (void* void* string) void*))

  (set! torch-std-requires-grad
    (foreign-procedure "torch_std_requires_grad" (void*) void*))
  (set! torch-std-set-requires-grad
    (foreign-procedure "torch_std_set_requires_grad" (void* int) void*))
  (set! torch-std-backward
    (foreign-procedure "torch_std_backward" (void*) void))
  (set! torch-std-backward-retain-graph
    (foreign-procedure "torch_std_backward_retain_graph" (void*) void))
  (set! torch-std-grad
    (foreign-procedure "torch_std_grad" (void*) void*))
  (set! torch-std-zero-grad
    (foreign-procedure "torch_std_zero_grad" (void*) void))
  (set! torch-std-has-grad
    (foreign-procedure "torch_std_has_grad" (void*) int))

  (set! torch-std-sgd-create
    (foreign-procedure "torch_std_sgd_create" (void* int double double double double int) void*))
  (set! torch-std-adam-create
    (foreign-procedure "torch_std_adam_create" (void* int double double double double double int) void*))
  (set! torch-std-adamw-create
    (foreign-procedure "torch_std_adamw_create" (void* int double double double double double int) void*))
  (set! torch-std-optimizer-step
    (foreign-procedure "torch_std_optimizer_step" (void*) void))
  (set! torch-std-optimizer-zero-grad
    (foreign-procedure "torch_std_optimizer_zero_grad" (void*) void))
  (set! torch-std-optimizer-destroy
    (foreign-procedure "torch_std_optimizer_destroy" (void*) void))

  (set! torch-std-narrow
    (foreign-procedure "torch_std_narrow" (void* long long long) void*))
  (set! torch-std-slice
    (foreign-procedure "torch_std_slice" (void* long long long long) void*))
  (set! torch-std-masked-select
    (foreign-procedure "torch_std_masked_select" (void* void*) void*))
  (set! torch-std-where
    (foreign-procedure "torch_std_where" (void* void* void*) void*))
  (set! torch-std-eq
    (foreign-procedure "torch_std_eq" (void* void*) void*))
  (set! torch-std-gt
    (foreign-procedure "torch_std_gt" (void* void*) void*))
  (set! torch-std-lt
    (foreign-procedure "torch_std_lt" (void* void*) void*))
  (set! torch-std-ge
    (foreign-procedure "torch_std_ge" (void* void*) void*))
  (set! torch-std-le
    (foreign-procedure "torch_std_le" (void* void*) void*))
  (set! torch-std-clamp
    (foreign-procedure "torch_std_clamp" (void* double double) void*))
  (set! torch-std-clip-grad-norm
    (foreign-procedure "torch_std_clip_grad_norm" (void* int double) void))

  (set! torch-std-manual-seed
    (foreign-procedure "torch_std_manual_seed" (long) void))
  (set! torch-std-cuda-is-available
    (foreign-procedure "torch_std_cuda_is_available" () int))
  (set! torch-std-to-cuda
    (foreign-procedure "torch_std_to_cuda" (void*) void*))
  (set! torch-std-to-cpu
    (foreign-procedure "torch_std_to_cpu" (void*) void*))
  (set! torch-std-is-cuda
    (foreign-procedure "torch_std_is_cuda" (void*) int))

  ;; ---- JIT module loading (new) ----
  (set! torch-std-jit-load
    (foreign-procedure "torch_std_jit_load" (string) void*))
  (set! torch-std-jit-forward
    (foreign-procedure "torch_std_jit_forward" (void* void*) void*))
  (set! torch-std-jit-parameters
    (foreign-procedure "torch_std_jit_parameters" (void* void* void* int) int))
  (set! torch-std-jit-module-delete
    (foreign-procedure "torch_std_jit_module_delete" (void*) void))

  ;; ---- SD UNet forward with LoRA ----
  (set! torch-std-sd-unet-forward
    (foreign-procedure "torch_std_sd_unet_forward"
      (void* int void* void* void* void* void* void* int double) void*))

  ;; ---- Image I/O ----
  (set! torch-std-load-image
    (foreign-procedure "torch_std_load_image" (string) void*))
  (set! torch-std-save-image
    (foreign-procedure "torch_std_save_image" (void* string int) void))

  ;; ---- DDPM scheduler ----
  (set! torch-std-ddpm-betas
    (foreign-procedure "torch_std_ddpm_betas" (int double double) void*))
  (set! torch-std-ddpm-add-noise
    (foreign-procedure "torch_std_ddpm_add_noise" (void* void* void* void*) void*))

  ;; ---- Named parameters ----
  (set! torch-std-jit-named-parameters
    (foreign-procedure "torch_std_jit_named_parameters" (void* void* void* int) int))

  ;; ---- State dict save ----
  (set! torch-std-save-state-dict
    (foreign-procedure "torch_std_save_state_dict" (void* string) int))

  ;; ---- safetensors loader ----
  (set! torch-std-safetensors-load
    (foreign-procedure "torch_std_safetensors_load" (string) void*))
  (set! torch-std-safetensors-count
    (foreign-procedure "torch_std_safetensors_count" (void*) int))
  (set! torch-std-safetensors-name
    (foreign-procedure "torch_std_safetensors_name" (void* int) string))
  (set! torch-std-safetensors-tensor
    (foreign-procedure "torch_std_safetensors_tensor" (void* int) void*))
  (set! torch-std-safetensors-free
    (foreign-procedure "torch_std_safetensors_free" (void*) void))
  (set! torch-std-safetensors-get-tensor-by-name
    (foreign-procedure "torch_std_safetensors_get_tensor_by_name" (void* string) void*))

  ;; ---- LoRA apply / merge ----
  (set! torch-std-lora-apply
    (foreign-procedure "torch_std_lora_apply" (void* void* void* double) void*))
  (set! torch-std-lora-merge-into
    (foreign-procedure "torch_std_lora_merge_into" (void* void* string double) int))

  ;; ---- Samplers (DDIM / Euler / Euler Ancestral / DPM++ 2M) ----
  (set! torch-std-sample-ddim
    (foreign-procedure "torch_std_sample_ddim" (void* void* void* void* double) void*))
  (set! torch-std-sample-euler
    (foreign-procedure "torch_std_sample_euler" (void* void* void* void*) void*))
  (set! torch-std-sample-euler-ancestral
    (foreign-procedure "torch_std_sample_euler_ancestral" (void* void* void* void*) void*))
  (set! torch-std-sample-dpmpp-2m
    (foreign-procedure "torch_std_sample_dpmpp_2m" (void* void* void* void* void* int) void*))
  (set! torch-std-sampler-sigmas
    (foreign-procedure "torch_std_sampler_sigmas" (int double double string) void*))

  ;; ---- Image processing ----
  (set! torch-std-image-resize
    (foreign-procedure "torch_std_image_resize" (void* int int string) void*))
  (set! torch-std-image-crop
    (foreign-procedure "torch_std_image_crop" (void* int int int int) void*))
  (set! torch-std-image-composite
    (foreign-procedure "torch_std_image_composite" (void* void* int int) void*))
  (set! torch-std-color-convert
    (foreign-procedure "torch_std_color_convert" (void* string string) void*))

  ;; ---- ControlNet ----
  (set! torch-std-controlnet-forward
    (foreign-procedure "torch_std_controlnet_forward" (void* int void* void* void* void* int) void*))
  (set! torch-std-controlnet-apply
    (foreign-procedure "torch_std_controlnet_apply" (void* void* double) void*))

  ;; ---- VAE tiling ----
  (set! torch-std-vae-encode-tiled
    (foreign-procedure "torch_std_vae_encode_tiled" (void* void* int int) void*))
  (set! torch-std-vae-decode-tiled
    (foreign-procedure "torch_std_vae_decode_tiled" (void* void* int int) void*))

  ;; ---- CLIP BPE tokenizer ----
  (set! torch-std-clip-tokenizer-create
    (foreign-procedure "torch_std_clip_tokenizer_create" (string string) void*))
  (set! torch-std-clip-tokenizer-encode
    (foreign-procedure "torch_std_clip_tokenizer_encode" (void* string) void*))
  (set! torch-std-clip-tokenizer-free
    (foreign-procedure "torch_std_clip_tokenizer_free" (void*) void))

  ;; ---- CLIP text encoder forward ----
  (set! torch-std-clip-text-forward
    (foreign-procedure "torch_std_clip_text_forward" (void* void* int) void*)))

;; ============================================================
;; Part 11a: tagged tensor 抽象：#(ptr shape-vec)
;; ============================================================
;; PyTorch tensor 统一包装：携带自身 shape，支持自动输出推断

(define (make-tagged-tensor ptr shape)
  (vector ptr shape))

(define (tagged-tensor-ptr t)
  (vector-ref t 0))

(define (tagged-tensor-shape t)
  (vector-ref t 1))

(define (tagged-tensor-ndim t)
  (vector-length (tagged-tensor-shape t)))

(define (tagged-tensor-dim t i)
  (vector-ref (tagged-tensor-shape t) i))

(define (tagged-tensor? x)
  (and (vector? x) (= (vector-length x) 2) (vector? (vector-ref x 1))))

;; 将 Scheme vector shape 转成 int64*，供 libTorch FFI 使用
(define (make-ffi-shape shape-vec)
  (let* ((ndim (vector-length shape-vec))
         (shape-ptr (foreign-alloc (if (fx= ndim 0) 8 (fx* ndim 8)))))
    (do ((i 0 (+ i 1))) ((= i ndim) shape-ptr)
      (foreign-set! 'long shape-ptr (* i 8) (vector-ref shape-vec i)))))

;; ============================================================
;; Part 11b: Python 风格包装 — libTorch Standard API 兼容层
;; ============================================================
;; 基于 Part 11 的 torch-std-* 原语，提供旧 API 风格的 torch.* 函数。

(define (torch-check msg thunk)
  (if *torch-available* (thunk) (begin (display msg) (newline) #f)))

(define (torch-available)
  "返回 libTorch 是否可用"
  *torch-available*)

(define (torch-tensor v)
  "从 Scheme vector / list 创建 float64 1D tensor"
  (torch-check "torch not available"
    (lambda ()
      (let* ((n (if (vector? v) (vector-length v) (length v)))
             (data (foreign-alloc (* n 8)))
             (shape-ptr (make-ffi-shape (vector n)))
             (dtype *torch-dtype-float64*))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'double data (* i 8)
            (if (vector? v) (vector-ref v i) (list-ref v i))))
        (make-tagged-tensor
          (torch-std-tensor-from-blob data shape-ptr 1 dtype)
          (vector n))))))

(define (torch-tensor-int64 v)
  "从 Scheme vector / list 创建 int64 1D tensor"
  (torch-check "torch not available"
    (lambda ()
      (let* ((n (if (vector? v) (vector-length v) (length v)))
             (data (foreign-alloc (* n 8)))
             (shape-ptr (make-ffi-shape (vector n)))
             (dtype *torch-dtype-int64*))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'long data (* i 8)
            (inexact->exact (floor (if (vector? v) (vector-ref v i) (list-ref v i))))))
        (make-tagged-tensor
          (torch-std-tensor-from-blob data shape-ptr 1 dtype)
          (vector n))))))

(define (torch-zeros . args)
  "创建全零 float64 tensor，接受 shape vector 或若干整数"
  (torch-check "torch not available"
    (lambda ()
      (let* ((shape-vec (if (and (= (length args) 1) (vector? (car args)))
                            (car args)
                            (list->vector args)))
             (ndim (vector-length shape-vec))
             (shape-ptr (make-ffi-shape shape-vec)))
        (make-tagged-tensor
          (torch-std-zeros shape-ptr ndim *torch-dtype-float64*)
          shape-vec)))))

(define (torch-ones . args)
  "创建全一 float64 tensor，接受 shape vector 或若干整数"
  (torch-check "torch not available"
    (lambda ()
      (let* ((shape-vec (if (and (= (length args) 1) (vector? (car args)))
                            (car args)
                            (list->vector args)))
             (ndim (vector-length shape-vec))
             (shape-ptr (make-ffi-shape shape-vec)))
        (make-tagged-tensor
          (torch-std-ones shape-ptr ndim *torch-dtype-float64*)
          shape-vec)))))

(define (torch-empty . args)
  "创建未初始化 float64 tensor，接受 shape vector 或若干整数"
  (torch-check "torch not available"
    (lambda ()
      (let* ((shape-vec (if (and (= (length args) 1) (vector? (car args)))
                            (car args)
                            (list->vector args)))
             (ndim (vector-length shape-vec))
             (shape-ptr (make-ffi-shape shape-vec)))
        (make-tagged-tensor
          (torch-std-empty shape-ptr ndim *torch-dtype-float64*)
          shape-vec)))))

(define (torch-add a b)
  "逐元素相加，返回新的 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-add (tagged-tensor-ptr a) (tagged-tensor-ptr b))
        (tagged-tensor-shape a)))))

(define (torch-mul a b)
  "逐元素相乘，返回新的 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-mul (tagged-tensor-ptr a) (tagged-tensor-ptr b))
        (tagged-tensor-shape a)))))

(define (torch-sub a b)
  "逐元素相减，返回新的 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-sub (tagged-tensor-ptr a) (tagged-tensor-ptr b))
        (tagged-tensor-shape a)))))

(define (torch-clone a)
  "拷贝 tensor，返回新的 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-clone (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-from-raw ptr)
  "把 C/C++ 返回的裸 tensor 指针包装为 tagged tensor（自动查询 shape）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto ptr))))

(define (torch-reshape a s)
  "reshape tensor，s 为 Scheme vector，如 #(2 3)"
  (torch-check "torch not available"
    (lambda ()
      (let ((shape-ptr (make-ffi-shape s))
            (ndim (vector-length s)))
        (make-tagged-tensor
          (torch-std-reshape (tagged-tensor-ptr a) shape-ptr ndim)
          s)))))

(define (torch-matmul a b)
  "矩阵乘法 C = A × B（任意维 batched matmul，含广播；形状实时查询）"
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-matmul (tagged-tensor-ptr a) (tagged-tensor-ptr b))))
        (if p
          (make-tagged-tensor p (torch-query-shape p))
          (begin (display "torch-matmul failed\n") #f))))))

(define (torch-to-list t)
  "将 tensor 数据复制为 Scheme vector（扁平化，按行优先）"
  (torch-check "torch not available"
    (lambda ()
      (let* ((ptr (tagged-tensor-ptr t))
             (n (torch-std-numel ptr))
             (data (foreign-alloc (* n 8)))
             (vec (make-vector n)))
        (torch-std-to-double-array ptr data n)
        (do ((i 0 (+ i 1))) ((= i n) vec)
          (vector-set! vec i (foreign-ref 'double data (* i 8))))))))

;; ============================================================
;; 张量方法运行时（transformers 风格 x.pow(2).mean(-1, keepdim=True)）
;; 由 static_translate 的 TENSOR_METHODS/TENSOR_ATTR_FN 生成 torch-tensor-* 调用
;; ============================================================

(define (torch-query-shape ptr)
  "从 tensor ptr 读取真实 shape -> Scheme vector（int64 dims）"
  (let* ((n (torch-std-ndim ptr))
         (buf (foreign-alloc (if (fx= n 0) 8 (fx* n 8)))))
    (torch-std-shape ptr buf)
    (let ((v (make-vector n)))
      (do ((i 0 (+ i 1))) ((= i n))
        (vector-set! v i (foreign-ref 'long buf (* i 8))))
      (foreign-free buf)
      v)))

(define (torch-tensor-binop std-fn a b)
  "张量二元运算（标量提升：非 tensor 操作数转 0 维 f32 tensor）"
  (let* ((pa (if (tagged-tensor? a)
                 (tagged-tensor-ptr a)
                 (torch-std-scalar-tensor-like (tagged-tensor-ptr b) (exact->inexact a))))
         (pb (if (tagged-tensor? b)
                 (tagged-tensor-ptr b)
                 (torch-std-scalar-tensor-like (tagged-tensor-ptr a) (exact->inexact b))))
         (p (std-fn pa pb)))
    (make-tagged-tensor p (torch-query-shape p))))

(define (torch-tensor-add a b) (torch-check "torch not available" (lambda () (torch-tensor-binop torch-std-add a b))))
(define (torch-tensor-sub a b) (torch-check "torch not available" (lambda () (torch-tensor-binop torch-std-sub a b))))
(define (torch-tensor-mul a b) (torch-check "torch not available" (lambda () (torch-tensor-binop torch-std-mul a b))))
(define (torch-tensor-div a b) (torch-check "torch not available" (lambda () (torch-tensor-binop torch-std-div a b))))

(define (torch-tensor-pow t e)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-pow (tagged-tensor-ptr t) (exact->inexact e))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-mean t dim keepdim)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-mean-dim (tagged-tensor-ptr t) dim (if keepdim 1 0))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-sum t dim keepdim)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-sum-dim (tagged-tensor-ptr t) dim (if keepdim 1 0))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-to t dtype)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-to-dtype (tagged-tensor-ptr t) dtype)))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-float t)
  (torch-tensor-to t 0))

(define (torch-tensor-dtype t)
  (torch-std-dtype (tagged-tensor-ptr t)))

(define (torch-tensor-shape t)
  (torch-query-shape (tagged-tensor-ptr t)))

(define (torch-tensor-ndim t)
  (torch-std-ndim (tagged-tensor-ptr t)))

(define (torch-tensor-sqrt t)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-sqrt (tagged-tensor-ptr t))
                                   (torch-query-shape (tagged-tensor-ptr t))))))

(define (torch-tensor-clone t)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-clone (tagged-tensor-ptr t))
                                   (tagged-tensor-shape t)))))

(define (torch-cos t)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-cos (tagged-tensor-ptr t)) (torch-query-shape (tagged-tensor-ptr t))))))
(define (torch-sin t)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-sin (tagged-tensor-ptr t)) (torch-query-shape (tagged-tensor-ptr t))))))
(define (torch-outer a b)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-outer (tagged-tensor-ptr a) (tagged-tensor-ptr b)) (torch-query-shape (tagged-tensor-ptr a))))))
(define (torch-rope-inv-freq dim base)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-rope-inv dim base) (vector (/ dim 2))))))
(define (torch-rope-t-pos seq off)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-arange-f-offset seq off) (vector seq)))))

(define (torch-rope-t seq)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-arange-f seq) (vector seq)))))
(define (torch-causal-mask s)
  (torch-check "torch not available" (lambda () (make-tagged-tensor (torch-std-causal-mask s) (vector s s)))))

(define (torch-tpack-index t ids)
  "torch.tpack_index(t, ids)：对 tpack 张量按 ids 取行（embed_tokens[ids]）"
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-index-rows2 (tagged-tensor-ptr t) (tagged-tensor-ptr ids))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-ptr-debug t)
  (tagged-tensor-ptr t))

(define (torch-cat-id ids v)
  "把标量 int 追加到 int64 ids 张量末尾，返回新张量"
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-cat-int64 (tagged-tensor-ptr ids) v)))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-narrow t dim start length)
  "torch.narrow: 沿 dim 取 [start, start+length)"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-narrow (tagged-tensor-ptr t) dim start length)
                          (torch-query-shape (tagged-tensor-ptr t))))))

(define (torch-last-argmax logits)
  "取 [1, s, V] 最后 token 的 argmax token id"
  (torch-check "torch not available"
    (lambda () (torch-std-last-argmax (tagged-tensor-ptr logits)))))

(define (torch-tpack-load path)
  "torch.tpack_load(path)：加载 TensorPack 权重（全局包），返回状态"
  (torch-std-tpack-load path))

(define (torch-tpack-get name)
  "torch.tpack_get(name)：取已加载权重为 float32 tagged tensor"
  (let ((p (torch-std-tpack-get name)))
    (if p (make-tagged-tensor p (torch-query-shape p)) #f)))

(define (torch-topk t k dim)
  "torch.topk(t,k,dim) -> Scheme vector [values, indices]（各为 tagged tensor）"
  (torch-check "torch not available"
    (lambda ()
      (let ((pv (torch-std-topk (tagged-tensor-ptr t) k dim 1))
            (pi (torch-std-topk (tagged-tensor-ptr t) k dim 0)))
        (vector (make-tagged-tensor pv (torch-query-shape pv))
                (make-tagged-tensor pi (torch-query-shape pi)))))))

(define (torch-rsqrt t)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-rsqrt (tagged-tensor-ptr t))
                                   (torch-query-shape (tagged-tensor-ptr t))))))

(define (torch-tensor-transpose-all t)
  (torch-check "torch not available"
    (lambda ()
      (let* ((n (torch-std-ndim (tagged-tensor-ptr t)))
             (p (if (fx<= n 2)
                    (torch-std-transpose (tagged-tensor-ptr t) 0 1)
                    (torch-std-transpose (tagged-tensor-ptr t) (- n 1) (- n 2)))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-unsqueeze t dim)
  (torch-check "torch not available"
    (lambda ()
      (let* ((ptr (tagged-tensor-ptr t))
             (dd (if (< dim 0) (+ (torch-std-ndim ptr) dim 1) dim))
             (p (torch-std-unsqueeze ptr dd)))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-squeeze t)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-squeeze (tagged-tensor-ptr t))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-contiguous t)
  t)

(define (torch-tensor-transpose t d0 d1)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-transpose (tagged-tensor-ptr t) d0 d1)
                                   (torch-query-shape (tagged-tensor-ptr t))))))

(define (torch-tensor-view . dims-args)
  (torch-check "torch not available"
    (lambda ()
      (let* ((t (car dims-args))
             (dims (cdr dims-args))
             (n (length dims))
             (buf (foreign-alloc (if (fx= n 0) 8 (fx* n 8)))))
        (do ((i 0 (+ i 1)) (d dims (cdr d))) ((= i n))
          (foreign-set! 'long buf (* i 8) (car d)))
        (let ((p (torch-std-reshape (tagged-tensor-ptr t) buf n)))
          (foreign-free buf)
          (make-tagged-tensor p (list->vector dims)))))))

(define (torch-tensor-reshape . dims-args)
  (apply torch-tensor-view dims-args))

(define (torch-tensor-permute t . dims)
  (torch-check "torch not available"
    (lambda ()
      (let* ((n (length dims))
             (buf (foreign-alloc (if (fx= n 0) 8 (fx* n 8)))))
        (do ((i 0 (+ i 1)) (d dims (cdr d))) ((= i n))
          (foreign-set! 'long buf (* i 8) (car d)))
        (let ((p (torch-std-permute (tagged-tensor-ptr t) buf n)))
          (foreign-free buf)
          (make-tagged-tensor p (torch-query-shape p)))))))

(define (torch-tensor-neg t)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-neg (tagged-tensor-ptr t))
                                   (torch-query-shape (tagged-tensor-ptr t))))))

(define (torch-tensor-slice-last t start end)
  "沿最后一维切片 [start, end)。end=-1 表示到末尾。返回张量（保持原维度数）"
  (torch-check "torch not available"
    (lambda ()
      (let* ((ptr (tagged-tensor-ptr t))
             (ndim (torch-std-ndim ptr))
             (buf (foreign-alloc (* ndim 8)))
             (dim (- ndim 1)))
        (torch-std-shape ptr buf)
        (let* ((last-len (foreign-ref 'long buf (* dim 8)))
               (hi (if (fx< end 0) last-len end))
               (p (torch-std-narrow ptr dim start (fx- hi start))))
          (foreign-free buf)
          (make-tagged-tensor p (torch-query-shape p)))))))

(define torch-tensor-index-select-raw #f)

(define (torch-tensor-index-select t idx)
  "t[idx]：高级索引取行（支持 1D/2D 任意形状 idx，语义同 python x[idx]）"
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-index-rows2 (tagged-tensor-ptr t) (tagged-tensor-ptr idx))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-cat . args)
  "torch.cat((a,b,...), dim)：首参为 tagged tensor 列表/vector，第二参 dim"
  (torch-check "torch not available"
    (lambda ()
      (let* ((ts (car args))
             (dim (if (pair? (cdr args)) (cadr args) 0))
             (n (vector-length ts))
             (buf (foreign-alloc (fx* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* buf (* i 8) (tagged-tensor-ptr (vector-ref ts i))))
        (let ((p (torch-std-cat buf n dim)))
          (foreign-free buf)
          (make-tagged-tensor p (torch-query-shape p)))))))


(define (torch-tensor-split t n dim)
  (torch-check "torch not available"
    (lambda () (list (torch-tensor-view t n dim)))))

(define (torch-tensor-expand t a b)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-expand (tagged-tensor-ptr t) a b)
                                   (vector a b)))))

(define (torch-tensor-max t dim keepdim)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-max-dim (tagged-tensor-ptr t) dim (if keepdim 1 0))))
        (make-tagged-tensor p (torch-query-shape p))))))

(define (torch-tensor-argmax t dim keepdim)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-argmax-dim1 (tagged-tensor-ptr t) dim)))
        (make-tagged-tensor p (vector))))))

(define (torch-tensor-softmax t dim)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-softmax (tagged-tensor-ptr t) dim)
                                   (tagged-tensor-shape t)))))

(define (torch-tensor-masked-fill t mask value)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-masked-fill (tagged-tensor-ptr t) (tagged-tensor-ptr mask) value)))
        (make-tagged-tensor p (tagged-tensor-shape t))))))

(define (torch-tensor-gather t dim index)
  (torch-check "torch not available"
    (lambda ()
      (let ((p (torch-std-gather (tagged-tensor-ptr t) dim (tagged-tensor-ptr index))))
        (make-tagged-tensor p (tagged-tensor-shape t))))))

(define (torch-tensor-narrow t dim start length)
  (torch-check "torch not available"
    (lambda () (make-tagged-tensor (torch-std-slice (tagged-tensor-ptr t) dim start length)
                                   (vector)))))

(define (torch-randn . args)
  "创建 float64 随机正态 tensor，接受 shape vector 或若干整数"
  (torch-check "torch not available"
    (lambda ()
      (let* ((shape-vec (if (and (= (length args) 1) (vector? (car args)))
                            (car args)
                            (list->vector args)))
             (ndim (vector-length shape-vec))
             (shape-ptr (make-ffi-shape shape-vec)))
        (make-tagged-tensor
          (torch-std-randn shape-ptr ndim *torch-dtype-float64*)
          shape-vec)))))

(define (torch-relu a)
  "ReLU 激活"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-relu (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-sigmoid a)
  "Sigmoid 激活"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-sigmoid (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-tanh a)
  "Tanh 激活"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-tanh (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-linear x w b)
  "线性层 y = x @ w^T + b"
  (torch-check "torch not available"
    (lambda ()
      (let* ((shape-x (tagged-tensor-shape x))
             (shape-w (tagged-tensor-shape w))
             (batch (vector-ref shape-x 0))
             (out (vector-ref shape-w 0)))
        (make-tagged-tensor
          (torch-std-linear (tagged-tensor-ptr x) (tagged-tensor-ptr w) (tagged-tensor-ptr b))
          (vector batch out))))))

(define (torch-mse-loss a b reduction)
  "MSE 损失，reduction 为 \"mean\" / \"sum\" / \"none\""
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-mse-loss (tagged-tensor-ptr a) (tagged-tensor-ptr b) reduction)
        (vector)))))

(define (torch-cross-entropy a b reduction)
  "交叉熵损失"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-cross-entropy-loss (tagged-tensor-ptr a) (tagged-tensor-ptr b) reduction)
        (vector)))))

(define (torch-backward loss)
  "对损失 tensor 执行反向传播"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-backward (tagged-tensor-ptr loss))
      #t)))

(define (torch-zero-grad t)
  "清零 tensor 的梯度"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-zero-grad (tagged-tensor-ptr t))
      #t)))

(define (torch-set-requires-grad t rg)
  "设置 tensor 是否需要梯度"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-set-requires-grad (tagged-tensor-ptr t) (if rg 1 0))
      #t)))

(define (torch-adam params lr)
  "从 tagged tensor 向量/列表创建 Adam 优化器"
  (torch-check "torch not available"
    (lambda ()
      (let* ((params-vec (if (list? params) (list->vector params) params))
             (n (vector-length params-vec))
             (ptrs (foreign-alloc (* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* ptrs (* i 8) (tagged-tensor-ptr (vector-ref params-vec i))))
        (torch-std-adam-create ptrs n lr 0.9 0.999 1e-8 0.0 0)))))

(define (torch-optimizer-step opt)
  "优化器单步更新"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-optimizer-step opt)
      #t)))

(define (torch-optimizer-zero-grad opt)
  "优化器清零梯度"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-optimizer-zero-grad opt)
      #t)))

;; 通用辅助：从裸 tensor 指针构造 tagged tensor，自动查询 shape
(define (make-tagged-tensor-auto ptr)
  (let* ((ndim (torch-std-ndim ptr))
         (shape-ptr (foreign-alloc (* ndim 8)))
         (shape (make-vector ndim)))
    (torch-std-shape ptr shape-ptr)
    (do ((i 0 (+ i 1))) ((= i ndim) (make-tagged-tensor ptr shape))
      (vector-set! shape i (foreign-ref 'long shape-ptr (* i 8))))))

(define (torch-conv2d input weight bias stride padding)
  "2D 卷积，stride/padding 为单个 int（square）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-conv2d (tagged-tensor-ptr input) (tagged-tensor-ptr weight) (tagged-tensor-ptr bias)
                          stride stride padding padding 1 1 1)))))

(define (torch-max-pool2d input kernel stride padding)
  "2D 最大池化，kernel/stride/padding 为单个 int（square）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-max-pool2d (tagged-tensor-ptr input) kernel kernel stride stride padding padding 1 1)))))

(define (torch-avg-pool2d input kernel stride padding)
  "2D 平均池化"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-avg-pool2d (tagged-tensor-ptr input) kernel kernel stride stride padding padding)))))

(define (torch-softmax a dim)
  "Softmax"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-softmax (tagged-tensor-ptr a) dim) (tagged-tensor-shape a)))))

(define (torch-log-softmax a dim)
  "Log-Softmax"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-log-softmax (tagged-tensor-ptr a) dim) (tagged-tensor-shape a)))))

(define (torch-sum a)
  "求和"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-sum (tagged-tensor-ptr a)) (vector)))))

(define (torch-mean a)
  "均值"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-mean (tagged-tensor-ptr a)) (vector)))))

(define (torch-argmax a)
  "返回扁平化 argmax"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-argmax (tagged-tensor-ptr a)))))

(define (torch-multinomial probs num-samples replacement)
  "多项式采样"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-multinomial (tagged-tensor-ptr probs) num-samples (if replacement 1 0))))))

(define (torch-cat tensors dim)
  "沿 dim 拼接 tensor 列表/向量"
  (torch-check "torch not available"
    (lambda ()
      (let* ((tvec (if (list? tensors) (list->vector tensors) tensors))
             (n (vector-length tvec))
             (ptrs (foreign-alloc (* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* ptrs (* i 8) (tagged-tensor-ptr (vector-ref tvec i))))
        (make-tagged-tensor-auto (torch-std-cat ptrs n dim))))))

(define (torch-stack tensors dim)
  "沿 dim 堆叠 tensor 列表/向量"
  (torch-check "torch not available"
    (lambda ()
      (let* ((tvec (if (list? tensors) (list->vector tensors) tensors))
             (n (vector-length tvec))
             (ptrs (foreign-alloc (* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* ptrs (* i 8) (tagged-tensor-ptr (vector-ref tvec i))))
        (make-tagged-tensor-auto (torch-std-stack ptrs n dim))))))

(define (torch-gather input dim index)
  "按 index tensor 收集元素"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-gather (tagged-tensor-ptr input) dim (tagged-tensor-ptr index))))))

(define (torch-index-select input dim index)
  "按 index tensor 选择切片"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-index-select (tagged-tensor-ptr input) dim (tagged-tensor-ptr index))))))

(define (torch-squeeze t dim)
  "移除指定维度为 1 的轴"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-squeeze (tagged-tensor-ptr t) dim)))))

(define (torch-unsqueeze t dim)
  "在指定位置插入大小为 1 的轴"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-unsqueeze (tagged-tensor-ptr t) dim)))))

(define (torch-transpose t dim0 dim1)
  "交换两个维度"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-transpose (tagged-tensor-ptr t) dim0 dim1)))))

(define (torch-manual-seed seed)
  "设置随机种子"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-manual-seed seed)
      #t)))

(define (torch-div a b)
  "逐元素相除"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-div (tagged-tensor-ptr a) (tagged-tensor-ptr b))
        (tagged-tensor-shape a)))))

(define (torch-pow a exp)
  "逐元素 a^exp"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-pow (tagged-tensor-ptr a) exp)
        (tagged-tensor-shape a)))))

(define (torch-exp a)
  "逐元素 exp"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-exp (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-log a)
  "逐元素 log"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-log (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-sqrt a)
  "逐元素 sqrt"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-sqrt (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-neg a)
  "逐元素取反"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-neg (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-abs a)
  "逐元素绝对值"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-abs (tagged-tensor-ptr a))
        (tagged-tensor-shape a)))))

(define (torch-clamp a lo hi)
  "截断到 [lo, hi]"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-clamp (tagged-tensor-ptr a) lo hi)
        (tagged-tensor-shape a)))))

(define (torch-sum-dim a dim keepdim)
  "按 dim 求和"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-sum-dim (tagged-tensor-ptr a) dim (if keepdim 1 0))))))

(define (torch-mean-dim a dim keepdim)
  "按 dim 求均值"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-mean-dim (tagged-tensor-ptr a) dim (if keepdim 1 0))))))

(define (torch-max-dim a dim keepdim)
  "按 dim 求最大值"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-max-dim (tagged-tensor-ptr a) dim (if keepdim 1 0))))))

(define (torch-min-dim a dim keepdim)
  "按 dim 求最小值"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-min-dim (tagged-tensor-ptr a) dim (if keepdim 1 0))))))

(define (torch-argmax-dim a dim)
  "按 dim 返回 argmax 索引（结果 shape 降维）"
  (torch-check "torch not available"
    (lambda ()
      (let* ((shape (tagged-tensor-shape a))
             (ndim (vector-length shape))
             (new-shape (make-vector (- ndim 1))))
        (do ((i 0 (+ i 1)) (j 0 j))
            ((= i ndim) new-shape)
          (when (not (= i dim))
            (vector-set! new-shape j (vector-ref shape i))
            (set! j (+ j 1))))
        (make-tagged-tensor
          (torch-std-argmax-dim1 (tagged-tensor-ptr a) dim)
          new-shape)))))

(define (torch-l1-loss a b reduction)
  "L1 损失"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-l1-loss (tagged-tensor-ptr a) (tagged-tensor-ptr b) reduction)
        (vector)))))

(define (torch-bce-loss a b reduction)
  "二分类交叉熵（输入已 sigmoid）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-bce-loss (tagged-tensor-ptr a) (tagged-tensor-ptr b) reduction)
        (vector)))))

(define (torch-bce-with-logits-loss a b reduction)
  "二分类交叉熵 + Sigmoid"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-bce-with-logits-loss (tagged-tensor-ptr a) (tagged-tensor-ptr b) reduction)
        (vector)))))

(define (torch-nll-loss a b reduction)
  "负对数似然损失"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor
        (torch-std-nll-loss (tagged-tensor-ptr a) (tagged-tensor-ptr b) reduction)
        (vector)))))

(define (torch-batch-norm1d input weight bias running-mean running-var training momentum eps)
  "1D BatchNorm"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-batch-norm1d
          (tagged-tensor-ptr input)
          (tagged-tensor-ptr weight)
          (tagged-tensor-ptr bias)
          (tagged-tensor-ptr running-mean)
          (tagged-tensor-ptr running-var)
          (if training 1 0) momentum eps)))))

(define (torch-batch-norm2d input weight bias running-mean running-var training momentum eps)
  "2D BatchNorm"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-batch-norm2d
          (tagged-tensor-ptr input)
          (tagged-tensor-ptr weight)
          (tagged-tensor-ptr bias)
          (tagged-tensor-ptr running-mean)
          (tagged-tensor-ptr running-var)
          (if training 1 0) momentum eps)))))

(define (torch-adamw params lr)
  "从 tagged tensor 向量/列表创建 AdamW 优化器"
  (torch-check "torch not available"
    (lambda ()
      (let* ((params-vec (if (list? params) (list->vector params) params))
             (n (vector-length params-vec))
             (ptrs (foreign-alloc (* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* ptrs (* i 8) (tagged-tensor-ptr (vector-ref params-vec i))))
        (torch-std-adamw-create ptrs n lr 0.9 0.999 1e-8 0.0 0)))))

(define (torch-sgd params lr momentum weight-decay)
  "从 tagged tensor 向量/列表创建 SGD 优化器"
  (torch-check "torch not available"
    (lambda ()
      (let* ((params-vec (if (list? params) (list->vector params) params))
             (n (vector-length params-vec))
             (ptrs (foreign-alloc (* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* ptrs (* i 8) (tagged-tensor-ptr (vector-ref params-vec i))))
        (torch-std-sgd-create ptrs n lr momentum 0.0 weight-decay 0)))))

(define (torch-clip-grad-norm params max-norm)
  "对 tagged tensor 列表/向量裁剪梯度范数"
  (torch-check "torch not available"
    (lambda ()
      (let* ((params-vec (if (list? params) (list->vector params) params))
             (n (vector-length params-vec))
             (ptrs (foreign-alloc (* n 8))))
        (do ((i 0 (+ i 1))) ((= i n))
          (foreign-set! 'void* ptrs (* i 8) (tagged-tensor-ptr (vector-ref params-vec i))))
        (torch-std-clip-grad-norm ptrs n max-norm)
        #t))))

(define (torch-cuda-is-available)
  "CUDA 是否可用"
  (torch-check "torch not available"
    (lambda ()
      (> (torch-std-cuda-is-available) 0))))

(define (torch-to-cuda t)
  "将 tensor 移到 CUDA"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-to-cuda (tagged-tensor-ptr t))))))

(define (torch-to-cpu t)
  "将 tensor 移回 CPU"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-to-cpu (tagged-tensor-ptr t))))))

(define (torch-is-cuda t)
  "tensor 是否在 CUDA 上"
  (torch-check "torch not available"
    (lambda ()
      (> (torch-std-is-cuda (tagged-tensor-ptr t)) 0))))

(define (torch-where condition x y)
  "按 condition 选择 x 或 y"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-where (tagged-tensor-ptr condition) (tagged-tensor-ptr x) (tagged-tensor-ptr y))))))

(define (torch-eq a b)
  "逐元素 =="
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-eq (tagged-tensor-ptr a) (tagged-tensor-ptr b)) (tagged-tensor-shape a)))))

(define (torch-gt a b)
  "逐元素 >"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-gt (tagged-tensor-ptr a) (tagged-tensor-ptr b)) (tagged-tensor-shape a)))))

(define (torch-lt a b)
  "逐元素 <"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-lt (tagged-tensor-ptr a) (tagged-tensor-ptr b)) (tagged-tensor-shape a)))))

(define (torch-ge a b)
  "逐元素 >="
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-ge (tagged-tensor-ptr a) (tagged-tensor-ptr b)) (tagged-tensor-shape a)))))

(define (torch-le a b)
  "逐元素 <="
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor (torch-std-le (tagged-tensor-ptr a) (tagged-tensor-ptr b)) (tagged-tensor-shape a)))))

(define (torch-detach a)
  "返回无梯度的 tensor 拷贝"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-detach (tagged-tensor-ptr a))))))

(define (torch-to-dtype a dtype)
  "转换 dtype，dtype: 0=float32, 1=float64, 2=int32, 3=int64"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-to-dtype (tagged-tensor-ptr a) dtype)))))

(define (torch-numel a)
  "tensor 元素总数"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-numel (tagged-tensor-ptr a)))))

(define (torch-grad a)
  "返回 tensor 的梯度"
  (torch-check "torch not available"
    (lambda ()
      (let ((g (torch-std-grad (tagged-tensor-ptr a))))
        (if g (make-tagged-tensor-auto g) #f)))))

(define (torch-has-grad a)
  "tensor 是否有梯度"
  (torch-check "torch not available"
    (lambda ()
      (> (torch-std-has-grad (tagged-tensor-ptr a)) 0))))

;; ====== JIT Module API ======

(define (torch-jit-load path)
  "加载 TorchScript traced 模块，返回 opaque 句柄"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-jit-load path))))

(define (torch-jit-forward module input)
  "运行 JIT 模块 forward，返回 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-jit-forward module (tagged-tensor-ptr input))))))

(define (torch-jit-parameters module)
  "返回 JIT 模块的所有参数 tensor 列表"
  (torch-check "torch not available"
    (lambda ()
      (let ((max-n 2000))
        (let ((ptrs (foreign-alloc (* max-n 8)))
              (names (foreign-alloc (* max-n 8))))
          (let ((n (torch-std-jit-parameters module ptrs names max-n)))
            (do ((i 0 (+ i 1)) (result '() (cons (vector-ref ptrs i) result)))
                ((= i n) (reverse result)))))))))

(define (torch-jit-delete module)
  "释放 JIT 模块"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-jit-module-delete module))))

;; ====== SD UNet Forward (autograd-aware, with LoRA) ======

(define (torch-sd-unet-forward weights n-weights input timestep text-emb
                               lora-A lora-B lora-indices n-lora lora-scale)
  "SD 1.5 UNet forward pass with optional LoRA injection.
weights:   vector of tagged tensors (all UNet parameters)
n-weights: number of weight tensors
input:     (B,4,H,W) latent
timestep:  (B,) float timesteps
text-emb:  (B,77,768) text embeddings
lora-A:    vector of LoRA A matrices (or empty)
lora-B:    vector of LoRA B matrices (or empty)
lora-indices: vector of int weight indices each LoRA targets
n-lora:    number of LoRA targets
lora-scale: LoRA scaling factor
Returns (B,4,H,W) output latent (autograd graph built)"
  (torch-check "torch not available"
    (lambda ()
      (let* ((w-vec (if (list? weights) (list->vector weights) weights))
             (n-w (vector-length w-vec))
             (w-ptrs (foreign-alloc (* n-w 8)))
             (la-vec (if (and lora-A (> n-lora 0)) (list->vector lora-A) (vector)))
             (lb-vec (if (and lora-B (> n-lora 0)) (list->vector lora-B) (vector)))
             (li-vec (if (and lora-indices (> n-lora 0)) (list->vector lora-indices) (vector)))
             (la-ptrs (foreign-alloc (max 1 (* n-lora 8))))
             (lb-ptrs (foreign-alloc (max 1 (* n-lora 8))))
             (li-ptrs (foreign-alloc (max 1 (* n-lora 8)))))
        ;; Fill weight pointers
        (do ((i 0 (+ i 1))) ((= i n-w))
          (foreign-set! 'void* w-ptrs (* i 8) (tagged-tensor-ptr (vector-ref w-vec i))))
        ;; Fill LoRA pointers
        (do ((i 0 (+ i 1))) ((= i n-lora))
          (foreign-set! 'void* la-ptrs (* i 8) (tagged-tensor-ptr (vector-ref la-vec i)))
          (foreign-set! 'void* lb-ptrs (* i 8) (tagged-tensor-ptr (vector-ref lb-vec i)))
          (foreign-set! 'long li-ptrs (* i 8) (inexact->exact (vector-ref li-vec i))))
        (make-tagged-tensor-auto
          (torch-std-sd-unet-forward
            w-ptrs n-w
            (tagged-tensor-ptr input)
            (tagged-tensor-ptr timestep)
            (tagged-tensor-ptr text-emb)
            la-ptrs lb-ptrs li-ptrs n-lora lora-scale))))))

;; ====== Image I/O ======

(define (torch-load-image path)
  "从文件加载图像，返回 tagged tensor (C,H,W) uint8"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-load-image path)))))

(define (torch-save-image tensor path as-pgm)
  "保存 tensor 为图像文件。as-pgm=1 输出灰度 PGM，否则 PPM"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-save-image (tagged-tensor-ptr tensor) path (if as-pgm 1 0)))))

;; ====== DDPM Scheduler ======

(define (torch-ddpm-betas T beta-start beta-end)
  "计算 DDPM beta 调度（线性），返回 tagged tensor (T,) float64"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-ddpm-betas T beta-start beta-end)))))

(define (torch-ddpm-add-noise latent noise timestep alphas-cumprod)
  "DDPM 加噪：noisy = sqrt(ac) * latent + sqrt(1-ac) * noise"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-ddpm-add-noise
          (tagged-tensor-ptr latent)
          (tagged-tensor-ptr noise)
          (tagged-tensor-ptr timestep)
          (tagged-tensor-ptr alphas-cumprod))))))

;; ====== State dict save ======

(define (torch-save-state-dict module path)
  "保存 JIT 模块状态字典到文件"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-save-state-dict module path))))

;; ====== safetensors loading ======

(define (torch-safetensors-load path)
  "加载 safetensors 文件，返回 opsque 字典句柄"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-safetensors-load path))))

(define (torch-safetensors-count dict)
  "返回 safetensors 字典中的 tensor 数量"
  (torch-std-safetensors-count dict))

(define (torch-safetensors-name dict idx)
  "返回 safetensors 字典中第 idx 个 tensor 的名称"
  (torch-std-safetensors-name dict idx))

(define (torch-safetensors-tensor dict idx)
  "返回 safetensors 字典中第 idx 个 tensor 的 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto (torch-std-safetensors-tensor dict idx)))))

(define (torch-safetensors-get-tensor-by-name dict name)
  "按名称从 safetensors 字典中获取 tensor"
  (torch-check "torch not available"
    (lambda ()
      (let ((ptr (torch-std-safetensors-get-tensor-by-name dict name)))
        (if (not ptr) #f (make-tagged-tensor-auto ptr))))))

(define (torch-safetensors-free dict)
  "释放 safetensors 字典"
  (torch-std-safetensors-free dict))

;; ====== LoRA primitives ======

(define (torch-lora-apply weight lora-A lora-B scale)
  "W' = W + scale * B @ A，返回新 tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-lora-apply
          (tagged-tensor-ptr weight)
          (tagged-tensor-ptr lora-A)
          (tagged-tensor-ptr lora-B)
          scale)))))

(define (torch-lora-merge-into model-dict lora-dict prefix scale)
  "将 LoRA 权重合并到模型字典中。prefix 如 'lora_unet_'。返回成功合并数"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-lora-merge-into model-dict lora-dict prefix scale))))

;; ====== Samplers ======

(define (torch-sample-ddim noise-pred x-t alpha-bar-t alpha-bar-prev eta)
  "DDIM 采样步：去噪 + 重加噪"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-sample-ddim
          (tagged-tensor-ptr noise-pred)
          (tagged-tensor-ptr x-t)
          (tagged-tensor-ptr alpha-bar-t)
          (tagged-tensor-ptr alpha-bar-prev)
          eta)))))

(define (torch-sample-euler noise-pred x-t sigma-t sigma-prev)
  "Euler 采样步"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-sample-euler
          (tagged-tensor-ptr noise-pred)
          (tagged-tensor-ptr x-t)
          (tagged-tensor-ptr sigma-t)
          (tagged-tensor-ptr sigma-prev))))))

(define (torch-sample-euler-ancestral noise-pred x-t sigma-t sigma-prev)
  "Euler Ancestral 采样步（加额外随机噪声）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-sample-euler-ancestral
          (tagged-tensor-ptr noise-pred)
          (tagged-tensor-ptr x-t)
          (tagged-tensor-ptr sigma-t)
          (tagged-tensor-ptr sigma-prev))))))

(define (torch-sample-dpmpp-2m noise-pred x-t sigma-t sigma-prev old-denoisd is-first-step)
  "DPM++ 2M 二阶采样步"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-sample-dpmpp-2m
          (tagged-tensor-ptr noise-pred)
          (tagged-tensor-ptr x-t)
          (tagged-tensor-ptr sigma-t)
          (tagged-tensor-ptr sigma-prev)
          (tagged-tensor-ptr old-denoisd)
          (if is-first-step 1 0))))))

(define (torch-sampler-sigmas steps sigma-min sigma-max schedule)
  "生成 sigma 调度 (steps+1,) 数组。schedule: 'karras'/'exponential'/'linear'"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-sampler-sigmas steps sigma-min sigma-max schedule)))))

;; ====== Image processing ======

(define (torch-image-resize-float img new-h new-w mode)
  "resize 图像返回 float tensor（模型输入用）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-image-resize-float (tagged-tensor-ptr img) new-h new-w mode)))))

(define (torch-image-resize img new-h new-w mode)
  "调整图像大小。mode: 'bilinear'/'nearest'/'bicubic'/'lanczos'"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-image-resize
          (tagged-tensor-ptr img) new-h new-w mode)))))

(define (torch-image-crop img x y w h)
  "裁切图像 (C,H,W) 从 (x,y) 取 (w,h) 区域"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-image-crop
          (tagged-tensor-ptr img) x y w h)))))

(define (torch-image-composite base overlay x y)
  "将 overlay 合成到 base 的 (x,y) 位置（需同样 dtype/device）"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-image-composite
          (tagged-tensor-ptr base)
          (tagged-tensor-ptr overlay) x y)))))

(define (torch-color-convert img from to)
  "色彩空间转换。from/to: 'rgb'/'hsv'/'ycbcr'"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-color-convert
          (tagged-tensor-ptr img) from to)))))

;; ====== ControlNet ======

(define (torch-controlnet-forward weights input timestep text-emb hint hint-channels)
  "ControlNet forward pass，返回控制特征列表"
  (torch-check "torch not available"
    (lambda ()
      (let* ((w-vec (if (list? weights) (list->vector weights) weights))
             (n-w (vector-length w-vec))
             (w-ptrs (foreign-alloc (* n-w 8))))
        (do ((i 0 (+ i 1))) ((= i n-w))
          (foreign-set! 'void* w-ptrs (* i 8) (tagged-tensor-ptr (vector-ref w-vec i))))
        (make-tagged-tensor-auto
          (torch-std-controlnet-forward
            w-ptrs n-w
            (tagged-tensor-ptr input)
            (tagged-tensor-ptr timestep)
            (tagged-tensor-ptr text-emb)
            (tagged-tensor-ptr hint)
            hint-channels))))))

(define (torch-controlnet-apply unet-features control-features strength)
  "将 ControlNet 特征注入 UNet 特征"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-controlnet-apply
          (tagged-tensor-ptr unet-features)
          (tagged-tensor-ptr control-features)
          strength)))))

;; ====== VAE tiling ======

(define (torch-vae-encode-tiled vae-module image tile-size overlap)
  "分块 VAE encode，返回 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-vae-encode-tiled
          vae-module
          (tagged-tensor-ptr image) tile-size overlap)))))

(define (torch-vae-decode-tiled vae-module latent tile-size overlap)
  "分块 VAE decode，返回 tagged tensor"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-vae-decode-tiled
          vae-module
          (tagged-tensor-ptr latent) tile-size overlap)))))

;; ====== CLIP BPE Tokenizer ======

(define (torch-clip-tokenizer-create vocab-path merges-path)
  "加载 CLIP BPE tokenizer（vocab.json + merges.txt），返回 opaque 句柄"
  (torch-check "torch not available"
    (lambda ()
      (torch-std-clip-tokenizer-create vocab-path merges-path))))

(define (torch-clip-tokenizer-encode tokenizer text)
  "将文本编码为 token_ids tensor (77,) int64，含 SOS/EOS/padding"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-clip-tokenizer-encode tokenizer text)))))

(define (torch-clip-tokenizer-free tokenizer)
  "释放 CLIP tokenizer"
  (torch-std-clip-tokenizer-free tokenizer))

;; ====== CLIP Text Encoder forward ======

(define (torch-clip-text-forward clip-module token-ids cast-to-float16)
  "CLIP text encoder forward: token_ids → (1,77,768) embeddings
clip-module: loaded JIT module
token-ids:   tagged tensor (77,) int64
cast-to-float16: 非零则输出转为 float16"
  (torch-check "torch not available"
    (lambda ()
      (make-tagged-tensor-auto
        (torch-std-clip-text-forward
          clip-module
          (tagged-tensor-ptr token-ids)
          (if cast-to-float16 1 0))))))

;; ====== nn 初始化辅助 ======

(define (nn-make-parameter t)
  "把 tensor 标记为 nn 可训练参数（包装对象，便于 Module 自动收集）"
  (vector 'nn-parameter t))

(define (nn-parameter? x)
  (and (vector? x) (= (vector-length x) 2) (eq? (vector-ref x 0) 'nn-parameter)))

(define (nn-parameter-tensor p)
  (vector-ref p 1))

(define (nn-wrap-parameter x)
  "如果 x 是 tensor 则包装为 parameter，否则保持原样"
  (if (tagged-tensor? x)
    (nn-make-parameter x)
    x))

(define (nn-module-make)
  "创建空 nn.Module 容器：#(module dict children vector params vector)"
  (vector 'nn-module (make-dict) (vector) (vector)))

(define (nn-module? x)
  (and (vector? x) (= (vector-length x) 4) (eq? (vector-ref x 0) 'nn-module)))

(define (nn-module-dict m)
  (vector-ref m 1))

(define (nn-module-children m)
  (vector-ref m 2))

(define (nn-module-params m)
  (vector-ref m 3))

(define (nn-module-register-parameter m name param)
  "注册一个参数到模块，同时加入内部参数列表"
  (dict-set! (nn-module-dict m) name param)
  (let ((old (nn-module-params m))
        (n (+ (vector-length (nn-module-params m)) 1)))
    (let ((new (make-vector n)))
      (do ((i 0 (+ i 1))) ((= i (- n 1)))
        (vector-set! new i (vector-ref old i)))
      (vector-set! new (- n 1) param)
      (vector-set! m 3 new))))

(define (nn-module-register-child m name child)
  "注册子模块"
  (dict-set! (nn-module-dict m) name child)
  (let ((old (nn-module-children m))
        (n (+ (vector-length (nn-module-children m)) 1)))
    (let ((new (make-vector n)))
      (do ((i 0 (+ i 1))) ((= i (- n 1)))
        (vector-set! new i (vector-ref old i)))
      (vector-set! new (- n 1) child)
      (vector-set! m 2 new))))

(define (nn-module-get m name)
  "读取模块属性/子模块/参数"
  (dict-get (nn-module-dict m) name))

(define (nn-module-collect-params m)
  "递归收集模块及其子模块的所有 parameter tensor（返回 vector）"
  (let ((result '()))
    (define (collect x)
      (cond
        ((nn-module? x)
         (do ((i 0 (+ i 1))) ((= i (vector-length (nn-module-params x))))
           (set! result (cons (nn-parameter-tensor (vector-ref (nn-module-params x) i)) result)))
         (do ((i 0 (+ i 1))) ((= i (vector-length (nn-module-children x))))
           (collect (vector-ref (nn-module-children x) i))))
        ((nn-parameter? x)
         (set! result (cons (nn-parameter-tensor x) result)))))
    (collect m)
    (list->vector (reverse result))))

(define (nn-module-call m x)
  "调用模块的 forward（模块必须有 'forward 键）"
  ((dict-get (nn-module-dict m) 'forward) m x))

(define (nn-Sequential . layers)
  "创建顺序容器：#(sequential layers vector)"
  (vector 'nn-sequential (list->vector layers)))

(define (nn-sequential? x)
  (and (vector? x) (= (vector-length x) 2) (eq? (vector-ref x 0) 'nn-sequential)))

(define (nn-sequential-layers s)
  (vector-ref s 1))

(define (nn-sequential-call s x)
  "顺序执行 layers，支持 nn.Module / function / tagged tensor parameter"
  (let loop ((i 0) (out x))
    (if (= i (vector-length (nn-sequential-layers s)))
      out
      (let ((layer (vector-ref (nn-sequential-layers s) i)))
        (loop (+ i 1)
          (cond
            ((nn-sequential? layer)
             (nn-sequential-call layer out))
            ((nn-module? layer)
             (nn-module-call layer out))
            ((procedure? layer)
             (layer out))
            ((tagged-tensor? layer)
             (torch-matmul out layer))
            (else
              (display "nn-sequential-call: unsupported layer type\n")
              out)))))))

(define (nn-sequential-parameters s)
  "收集 Sequential 内所有可训练参数"
  (let ((result '()))
    (do ((i 0 (+ i 1))) ((= i (vector-length (nn-sequential-layers s))))
      (let ((layer (vector-ref (nn-sequential-layers s) i)))
        (cond
          ((nn-module? layer)
           (set! result (append result (vector->list (nn-module-collect-params layer)))))
          ((nn-sequential? layer)
           (set! result (append result (vector->list (nn-sequential-parameters layer))))))))
    (list->vector result)))

(define (nn-linear in-features out-features)
  "创建 nn.Linear 模块"
  (let* ((m (nn-module-make))
         (w (torch-randn out-features in-features))
         (b (torch-randn out-features)))
    (torch-set-requires-grad w #t)
    (torch-set-requires-grad b #t)
    (nn-module-register-parameter m 'weight (nn-make-parameter w))
    (nn-module-register-parameter m 'bias (nn-make-parameter b))
    (dict-set! (nn-module-dict m) 'forward
      (lambda (self x)
        (torch-linear x
          (nn-parameter-tensor (nn-module-get self 'weight))
          (nn-parameter-tensor (nn-module-get self 'bias)))))
    m))

(define (nn-conv2d in-channels out-channels kernel stride padding)
  "创建 nn.Conv2d 模块（square kernel/stride/padding）"
  (let* ((m (nn-module-make))
         (w (torch-randn out-channels in-channels kernel kernel))
         (b (torch-randn out-channels)))
    (torch-set-requires-grad w #t)
    (torch-set-requires-grad b #t)
    (nn-module-register-parameter m 'weight (nn-make-parameter w))
    (nn-module-register-parameter m 'bias (nn-make-parameter b))
    (dict-set! (nn-module-dict m) 'stride stride)
    (dict-set! (nn-module-dict m) 'padding padding)
    (dict-set! (nn-module-dict m) 'forward
      (lambda (self x)
        (torch-conv2d x
          (nn-parameter-tensor (nn-module-get self 'weight))
          (nn-parameter-tensor (nn-module-get self 'bias))
          (dict-get (nn-module-dict self) 'stride)
          (dict-get (nn-module-dict self) 'padding))))
    m))

(define (nn-batch-norm2d num-features)
  "创建 nn.BatchNorm2d 模块"
  (let* ((m (nn-module-make))
         (w (torch-ones num-features))
         (b (torch-zeros num-features))
         (rm (torch-zeros num-features))
         (rv (torch-ones num-features)))
    (torch-set-requires-grad w #t)
    (torch-set-requires-grad b #t)
    (nn-module-register-parameter m 'weight (nn-make-parameter w))
    (nn-module-register-parameter m 'bias (nn-make-parameter b))
    (nn-module-register-parameter m 'running_mean (nn-make-parameter rm))
    (nn-module-register-parameter m 'running_var (nn-make-parameter rv))
    (dict-set! (nn-module-dict m) 'training #t)
    (dict-set! (nn-module-dict m) 'momentum 0.1)
    (dict-set! (nn-module-dict m) 'eps 1e-5)
    (dict-set! (nn-module-dict m) 'forward
      (lambda (self x)
        (torch-batch-norm2d x
          (nn-parameter-tensor (nn-module-get self 'weight))
          (nn-parameter-tensor (nn-module-get self 'bias))
          (nn-parameter-tensor (nn-module-get self 'running_mean))
          (nn-parameter-tensor (nn-module-get self 'running_var))
          (dict-get (nn-module-dict self) 'training)
          (dict-get (nn-module-dict self) 'momentum)
          (dict-get (nn-module-dict self) 'eps))))
    m))

(define (nn-relu)
  "返回 ReLU 函数层"
  torch-relu)

(define (nn-sigmoid)
  "返回 Sigmoid 函数层"
  torch-sigmoid)

(define (nn-tanh)
  "返回 Tanh 函数层"
  torch-tanh)

(define (nn-flatten)
  "返回 flatten 函数层：把 4D 卷积输出 reshape 为 2D"
  (lambda (x)
    (let* ((shape (tagged-tensor-shape x))
           (batch (vector-ref shape 0))
           (feat  (apply * (cdr (vector->list shape)))))
      (torch-reshape x (vector batch feat)))))

(define (nn-parameters model)
  "收集模型所有可训练参数，返回 vector，可用于 torch.adam / torch.sgd"
  (cond
    ((nn-module? model) (nn-module-collect-params model))
    ((nn-sequential? model) (nn-sequential-parameters model))
    (else (vector))))

(define (nn-call model x)
  "统一调用模型/Sequential"
  (cond
    ((nn-module? model) (nn-module-call model x))
    ((nn-sequential? model) (nn-sequential-call model x))
    ((procedure? model) (model x))
    (else (display "nn-call: unsupported model type\n") x)))
