#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include<stdio.h>
#include<iostream>
#include<math.h>
#include<time.h>

//namespace for standard lib.
using namespace std;

//STEP 0 & 5 : Start calculate SSR : (sum of square of residual SSR, calcualte deviation of 
//predicted value of ALL point vs. mean of dataset)
__global__ void calculate_error_points(float* totalError, double* b, double* m,
	float* pointX, float* pointY, int num_points)
{
	int i = threadIdx.x; //get processor
	for (i; i < num_points; i++)
	{
		totalError[i] = powf((pointY[i] - (*m * pointX[i] + *b)), 2.0);
	}
}
//STEP 4   : Before calculate SSR : Calculate for distance between line and points
float compute_error_for_line_given_points(double* b, double* m, float* pointX, float* pointY, int num_points)
{
	float pointError[100] = { 0.0, };
	float totalError = 0.0;
	float ret = 0.0;
	float* d_pointX, * d_pointY, * d_pointError;
	double* d_b, * d_m;

	//alocate GPU memory
	cudaMalloc(&d_pointX, 100 * sizeof(float));
	cudaMalloc(&d_pointY, 100 * sizeof(float));
	cudaMalloc(&d_pointError, 100 * sizeof(float));
	cudaMalloc(&d_b, sizeof(double));
	cudaMalloc(&d_m, sizeof(double));

	//copy CPU data to GPU memory
	cudaMemcpy(d_pointX, pointX, 100 * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_pointY, pointY, 100 * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_pointError, pointError, 100 * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_b, b, sizeof(double), cudaMemcpyHostToDevice);
	cudaMemcpy(d_m, m, sizeof(double), cudaMemcpyHostToDevice);


	//caluation error between line and points
	calculate_error_points << <1, 100 >> > (d_pointError, d_b, d_m, d_pointX, d_pointY, num_points);//1 block 100thread
	//copy back data 
	cudaMemcpy(pointError, d_pointError, 100 * sizeof(float), cudaMemcpyDeviceToHost);

	for (int i = 0; i < 100; i++) {
		totalError += pointError[i];
	}
	ret = (totalError / float(num_points));

	//free memory
	cudaFree(d_pointX);
	cudaFree(d_pointY);
	cudaFree(d_pointError);
	cudaFree(d_b);
	cudaFree(d_m);

	return ret;
}

//STEP 3   : Start training: calculation gradient for updating weight - for backpropagation.
__global__ void calculate_step_gradient(float* d_b_gradient, float* d_m_gradient,
	float* d_N, double* d_new_b, double* d_new_m, double* d_b_current,
	double* d_m_current, float* d_pointX, float* d_pointY, float* d_learningRate, int num_points) {

	int i = threadIdx.x;

	for (int i; i < num_points; i++) { //MeanSqErr (is the point best fit?, at A certain point)
		*d_b_gradient += -(2 / (*d_N)) * (d_pointY[i] - ((*d_m_current * d_pointX[i]) + *d_b_current));

		*d_m_gradient += -(2 / (*d_N)) * d_pointX[i] * (d_pointY[i] - ((*d_m_current * d_pointX[i]) + *d_b_current));

		*d_new_b = *d_b_current - (*d_learningRate * (*d_b_gradient)); //minus bcos go neg direction

		*d_new_m = *d_m_current - (*d_learningRate * (*d_m_gradient)); // learning rate how far is each step 
	}
}
//STEP 2   : before training
void step_gradient(double* new_b, double* new_m, double* b_current, double* m_current, float* pointX, float* pointY, float learningRate, int num_points) {
	float b_gradient = 0.0;
	float m_gradient = 0.0;
	float N = float(num_points);

	float* d_pointX, * d_pointY;
	float* d_b_gradient, * d_m_gradient, * d_N, * d_learningRate;
	double* d_new_b, * d_new_m, * d_b_current, * d_m_current;

	//alocate
	cudaMalloc((void**)&d_pointX, 100 * sizeof(float));
	cudaMalloc((void**)&d_pointY, 100 * sizeof(float));
	cudaMalloc((void**)&d_b_gradient, sizeof(float));
	cudaMalloc((void**)&d_m_gradient, sizeof(float));
	cudaMalloc((void**)&d_N, sizeof(float));
	cudaMalloc((void**)&d_new_b, sizeof(double));
	cudaMalloc((void**)&d_new_m, sizeof(double));
	cudaMalloc((void**)&d_b_current, sizeof(double));
	cudaMalloc((void**)&d_m_current, sizeof(double));
	cudaMalloc((void**)&d_learningRate, sizeof(float));
	//copy
	cudaMemcpy(d_pointX, pointX, 100 * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_pointY, pointY, 100 * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_b_gradient, &b_gradient, sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_m_gradient, &m_gradient, sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_N, &N, sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(d_new_b, new_b, sizeof(double), cudaMemcpyHostToDevice);
	cudaMemcpy(d_new_m, new_m, sizeof(double), cudaMemcpyHostToDevice);
	cudaMemcpy(d_b_current, b_current, sizeof(double), cudaMemcpyHostToDevice);
	cudaMemcpy(d_m_current, m_current, sizeof(double), cudaMemcpyHostToDevice);
	cudaMemcpy(d_learningRate, &learningRate, sizeof(float), cudaMemcpyHostToDevice);

	calculate_step_gradient << <1, 100 >> > (d_b_gradient, d_m_gradient,
		d_N, d_new_b, d_new_m, d_b_current, d_m_current, d_pointX, d_pointY, d_learningRate, num_points);

	cudaMemcpy(new_b, d_new_b, sizeof(double), cudaMemcpyDeviceToHost);
	cudaMemcpy(new_m, d_new_m, sizeof(double), cudaMemcpyDeviceToHost);
	//printf("new_b: %f, new_m: %f\n", *new_b, *new_m);
}
//STEP 1   : new bias and weight update" backpropagation"
void gradient_descent_runner(double* b, double* m, float* pointX, float* pointY, float starting_b, float starting_m, float learning_rate, int num_iterations)
{
	*b = starting_b;
	*m = starting_m;
	double new_b = 0;
	double new_m = 0;

	for (int i = 0; i < num_iterations; i++)
	{
		step_gradient(&new_b, &new_m, b, m, pointX, pointY, learning_rate, 100);
		*b = new_b;
		*m = new_m;
		//printf("d_b_current: %f, d_m_current: %f\n", new_b, new_m);// repeat and display current y=mx+c
	}
}

int main()
{
	//check time interval
	clock_t begin, end;
	//start
	begin = clock();

	float f1 = 0, f2 = 0;
	float pointX[100] = { 0 }, pointY[100] = { 0 };
	FILE* fp;
	// read Csv
	fp = fopen("C:/Users/Administrator/Desktop/test.csv", "r");
	int i = 0;
	while (fscanf(fp, "%g,%g\n", &f1, &f2) == 2)
	{
		pointX[i] = f1;
		pointY[i] = f2;
		//		printf("%g, %g\n", f1, f2);
		i++;
	}

	//y= m x + b
	float learning_rate = 0.0001;
	double initial_b = 1;
	double initial_m = 1;
	int num_iterations = 10000;
	float error = 0;
	double b = 0.0;
	double m = 0.0;

	//calculate first total error
	error = compute_error_for_line_given_points(&initial_b, &initial_m, pointX, pointY, 100);//send init point and([][])
	printf("Generated initial gradient descent at b = %f, m = %f, error = %f\n", initial_b, initial_m, error);
	printf("Training...\n");

	//train
	gradient_descent_runner(&b, &m, pointX, pointY, initial_b, initial_m, learning_rate, num_iterations);

	//calculate error after update (backpropagation)
	error = compute_error_for_line_given_points(&b, &m, pointX, pointY, 100);
	printf("After %d iterations b = %f, m = %f, error = %f\nFinal model = y = %fx + %f\n", num_iterations, b, m, error, m, b);

	//end 
	end = clock();
	printf("GPU time inverval : %d msec\n", (end - begin));
	return 0;
}