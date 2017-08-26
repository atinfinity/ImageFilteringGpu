﻿#include "imageFilteringGpu.cuh"

#include <opencv2/core/cuda/common.hpp>
#include <opencv2/cudev.hpp>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>

texture<uchar, cudaTextureType2D, cudaReadModeElementType> srcTex(false, cudaFilterModePoint, cudaAddressModeClamp);

__device__ uchar clipGpu(float val)
{
	return (val < 0.0f) ? 0 : (val > 255.0f) ? 255 : (uchar)val;
}

__global__ void imageFilteringGpu
(
    const cv::cudev::PtrStepSz<uchar> src,
    cv::cudev::PtrStepSz<uchar> dst,
    const cv::cudev::PtrStepSz<float> kernel, 
    const int border_size
)
{
    const int x = blockDim.x * blockIdx.x + threadIdx.x;
    const int y = blockDim.y * blockIdx.y + threadIdx.y;

    if((y >= border_size) && y < (dst.rows-border_size)){
        if((x >= border_size) && (x < (dst.cols-border_size))){
            float sum = 0.0f;
            for(int yy = 0; yy < kernel.rows; yy++){
                for(int xx = 0; xx < kernel.cols; xx++){
                    sum = __fadd_rn(sum, __fmul_rn(kernel.ptr(yy)[xx], src.ptr(y+yy-border_size)[x+xx-border_size]));
                }
            }
            dst.ptr(y)[x] = clipGpu(sum);
        }
    }
}

// use __ldg
__global__ void imageFilteringGpu_ldg
(
    const cv::cudev::PtrStepSz<uchar> src,
    cv::cudev::PtrStepSz<uchar> dst,
    const cv::cudev::PtrStepSz<float> kernel, 
    const int border_size
)
{
    const int x = blockDim.x * blockIdx.x + threadIdx.x;
    const int y = blockDim.y * blockIdx.y + threadIdx.y;

    if((y >= border_size) && y < (dst.rows-border_size)){
        if((x >= border_size) && (x < (dst.cols-border_size))){
            float sum = 0.0f;
            for(int yy = 0; yy < kernel.rows; yy++){
                const uchar* psrc = src.ptr(y+yy-border_size) + (x-border_size);
                const float* pkernel = kernel.ptr(yy);
                for(int xx = 0; xx < kernel.cols; xx++){
                    sum = __fadd_rn(sum, __fmul_rn(__ldg(&pkernel[xx]), __ldg(&psrc[xx])));
                }
            }
            dst.ptr(y)[x] = sum;
        }
    }
}

// use texture
__global__ void imageFilteringGpu_tex
(
    const cv::cudev::PtrStepSz<uchar> src,
    cv::cudev::PtrStepSz<uchar> dst,
    const cv::cudev::PtrStepSz<float> kernel, 
    const int border_size
)
{
    const int x = blockDim.x * blockIdx.x + threadIdx.x;
    const int y = blockDim.y * blockIdx.y + threadIdx.y;

    if((y >= border_size) && (y < (dst.rows-border_size))){
        if((x >= border_size) && (x < (dst.cols-border_size))){
            float sum = 0.0f;
            for(int yy = 0; yy < kernel.rows; yy++){
                for(int xx = 0; xx < kernel.cols; xx++){
                    sum = __fadd_rn(sum, __fmul_rn(kernel.ptr(yy)[xx], tex2D(srcTex, x + xx - border_size, y + yy - border_size)));
                }
            }
            dst.ptr(y)[x] = sum;
        }
    }
}

void launchImageFilteringGpu
(
    cv::cuda::GpuMat& src,
    cv::cuda::GpuMat& dst,
    cv::cuda::GpuMat& kernel, 
    const int border_size
)
{
    cv::cudev::PtrStepSz<uchar> pSrc =
        cv::cudev::PtrStepSz<uchar>(src.rows, src.cols * src.channels(), src.ptr<uchar>(), src.step);

    cv::cudev::PtrStepSz<uchar> pDst =
        cv::cudev::PtrStepSz<uchar>(dst.rows, dst.cols * dst.channels(), dst.ptr<uchar>(), dst.step);

    cv::cudev::PtrStepSz<float> pKernel =
        cv::cudev::PtrStepSz<float>(kernel.rows, kernel.cols * kernel.channels(), kernel.ptr<float>(), kernel.step);

    const dim3 block(64, 2);
    const dim3 grid(cv::cudev::divUp(dst.cols, block.x), cv::cudev::divUp(dst.rows, block.y));

    imageFilteringGpu<<<grid, block>>>(pSrc, pDst, pKernel, border_size);

    CV_CUDEV_SAFE_CALL(cudaGetLastError());
    CV_CUDEV_SAFE_CALL(cudaDeviceSynchronize());
}

// use __ldg
void launchImageFilteringGpu_ldg
(
    cv::cuda::GpuMat& src,
    cv::cuda::GpuMat& dst,
    cv::cuda::GpuMat& kernel, 
    const int border_size
)
{
    cv::cudev::PtrStepSz<uchar> pSrc =
        cv::cudev::PtrStepSz<uchar>(src.rows, src.cols * src.channels(), src.ptr<uchar>(), src.step);

    cv::cudev::PtrStepSz<uchar> pDst =
        cv::cudev::PtrStepSz<uchar>(dst.rows, dst.cols * dst.channels(), dst.ptr<uchar>(), dst.step);

    cv::cudev::PtrStepSz<float> pKernel =
        cv::cudev::PtrStepSz<float>(kernel.rows, kernel.cols * kernel.channels(), kernel.ptr<float>(), kernel.step);

    const dim3 block(64, 2);
    const dim3 grid(cv::cudev::divUp(dst.cols, block.x), cv::cudev::divUp(dst.rows, block.y));

    imageFilteringGpu_ldg<<<grid, block>>>(pSrc, pDst, pKernel, border_size);

    CV_CUDEV_SAFE_CALL(cudaGetLastError());
    CV_CUDEV_SAFE_CALL(cudaDeviceSynchronize());
}

// use texture
void launchImageFilteringGpu_tex
(
    cv::cuda::GpuMat& src,
    cv::cuda::GpuMat& dst,
    cv::cuda::GpuMat& kernel, 
    const int border_size
)
{
    cv::cudev::PtrStepSz<uchar> pSrc =
        cv::cudev::PtrStepSz<uchar>(src.rows, src.cols * src.channels(), src.ptr<uchar>(), src.step);

    cv::cudev::PtrStepSz<uchar> pDst =
        cv::cudev::PtrStepSz<uchar>(dst.rows, dst.cols * dst.channels(), dst.ptr<uchar>(), dst.step);

    cv::cudev::PtrStepSz<float> pKernel =
        cv::cudev::PtrStepSz<float>(kernel.rows, kernel.cols * kernel.channels(), kernel.ptr<float>(), kernel.step);

    // bind texture
    cv::cuda::device::bindTexture<uchar>(&srcTex, pSrc);

    const dim3 block(64, 2);
    const dim3 grid(cv::cudev::divUp(dst.cols, block.x), cv::cudev::divUp(dst.rows, block.y));

    imageFilteringGpu_tex<<<grid, block>>>(pSrc, pDst, pKernel, border_size);

    CV_CUDEV_SAFE_CALL(cudaGetLastError());
    CV_CUDEV_SAFE_CALL(cudaDeviceSynchronize());

    // unbind texture
    CV_CUDEV_SAFE_CALL(cudaUnbindTexture(srcTex));
}

double launchImageFilteringGpu
(
    cv::cuda::GpuMat& src,
    cv::cuda::GpuMat& dst,
    cv::cuda::GpuMat& kernel, 
    const int border_size, 
    const int loop_num
)
{
    double f = 1000.0f / cv::getTickFrequency();
    int64 start = 0, end = 0;
    double time = 0.0;
    for (int i = 0; i <= loop_num; i++){
        start = cv::getTickCount();
        launchImageFilteringGpu(src, dst, kernel, border_size);
        end = cv::getTickCount();
        time += (i > 0) ? ((end - start) * f) : 0;
    }
    time /= loop_num;

    return time;
}

double launchImageFilteringGpu_ldg
(
    cv::cuda::GpuMat& src,
    cv::cuda::GpuMat& dst,
    cv::cuda::GpuMat& kernel, 
    const int border_size, 
    const int loop_num
)
{
    double f = 1000.0f / cv::getTickFrequency();
    int64 start = 0, end = 0;
    double time = 0.0;
    for (int i = 0; i <= loop_num; i++){
        start = cv::getTickCount();
        launchImageFilteringGpu_ldg(src, dst, kernel, border_size);
        end = cv::getTickCount();
        time += (i > 0) ? ((end - start) * f) : 0;
    }
    time /= loop_num;

    return time;
}

double launchImageFilteringGpu_tex
(
    cv::cuda::GpuMat& src,
    cv::cuda::GpuMat& dst,
    cv::cuda::GpuMat& kernel, 
    const int border_size, 
    const int loop_num
)
{
    double f = 1000.0f / cv::getTickFrequency();
    int64 start = 0, end = 0;
    double time = 0.0;
    for (int i = 0; i <= loop_num; i++){
        start = cv::getTickCount();
        launchImageFilteringGpu_tex(src, dst, kernel, border_size);
        end = cv::getTickCount();
        time += (i > 0) ? ((end - start) * f) : 0;
    }
    time /= loop_num;

    return time;
}
